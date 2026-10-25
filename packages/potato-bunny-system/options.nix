# Options for the potato-bunny system layer. Deliberately tiny: this is not
# NixOS, just enough structure to describe the few things the layer owns on
# DSM — files under /etc/nix, systemd units, and accounts that `activate`
# reconciles through synouser/synogroup.
{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption types;

  unitType = types.submodule ({name, ...}: {
    options = {
      text = mkOption {
        type = types.str;
        description = "Unit file contents.";
      };
      wantedBy = mkOption {
        type = types.listOf types.str;
        # Drop-ins ("foo.service.d/bar.conf") extend another unit and are never wanted themselves.
        default =
          if lib.hasInfix "/" name
          then []
          else ["multi-user.target"];
        description = "Targets whose .wants directory links this unit.";
      };
      restartIfChanged = mkOption {
        type = types.bool;
        default = true;
        description = "Restart the unit when its contents change between generations.";
      };
    };
  });
in {
  options = {
    assertions = mkOption {
      type = types.listOf types.unspecified;
      internal = true;
      default = [];
    };

    environment.etc = mkOption {
      type = types.attrsOf (types.submodule {
        options.text = mkOption {type = types.str;};
      });
      default = {};
      description = "Files to write under /etc, keyed by path relative to /etc.";
    };

    systemd.units = mkOption {
      type = types.attrsOf unitType;
      default = {};
      description = ''
        Units linked into /etc/systemd/system. Names may contain one "/" to
        declare a drop-in, e.g. "user@1027.service.d/nix-system.conf".
      '';
    };

    systemd.extraWants = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = {};
      description = "Units not declared here (e.g. DSM's user@.service instances) to add to a target's .wants.";
    };

    users.users = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          description = mkOption {
            type = types.str;
            default = "";
          };
          extraGroups = mkOption {
            type = types.listOf types.str;
            default = [];
          };
        };
      });
      default = {};
      description = "Service accounts created with synouser. Never deleted.";
    };

    users.groups = mkOption {
      type = types.attrsOf (types.submodule {
        options.members = mkOption {
          type = types.listOf types.str;
          default = [];
        };
      });
      default = {};
      description = "Groups whose membership activate sets to exactly `members`.";
    };

    homeUsers = mkOption {
      type = types.attrsOf (types.submodule {
        options.uid = mkOption {type = types.int;};
      });
      default = {};
      description = "Users whose systemd user manager runs from boot, for home-manager services.";
    };

    nix.package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "Lix for the daemon and the root default profile.";
    };

    profileExtra = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Extra packages in the root default profile alongside nix.package.";
    };
  };

  config.assertions =
    lib.mapAttrsToList (path: _: {
      assertion = lib.hasPrefix "nix/" path && lib.all (c: c != "" && c != "." && c != "..") (lib.splitString "/" path);
      message = "environment.etc.\"${path}\": only plain paths under /etc/nix are managed (the rest of /etc belongs to DSM).";
    })
    config.environment.etc
    ++ lib.mapAttrsToList (name: _: {
      assertion = lib.hasPrefix "svc-" name;
      message = "users.users.${name}: service accounts must be named svc-<service>.";
    })
    config.users.users
    ++ lib.mapAttrsToList (name: _: {
      assertion = builtins.match "[A-Za-z0-9@_.:-]+(\\.d/[A-Za-z0-9@_.:-]+)?" name != null && !(lib.hasInfix ".." name);
      message = "systemd.units.\"${name}\": must be a unit name or one drop-in (\"foo.service.d/bar.conf\").";
    })
    config.systemd.units;
}
