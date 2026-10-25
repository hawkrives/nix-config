# Options for the potato-bunny system layer. Deliberately small: this is not
# NixOS, just enough structure to describe what the layer owns on DSM —
# files under /etc/nix, systemd units, accounts that `activate` reconciles
# through synouser/synogroup, and DSM tasks, packages and settings it
# reconciles through DSM's own tools and web APIs.
{
  lib,
  config,
  pkgs,
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

  knownServices = import ./services.nix;

  # The settings that switch a built-in feature on or off, set from `enable`.
  enableSetting = {
    smb = "enable_samba";
    ssh = "enable_ssh";
  };

  serviceType = types.submodule ({
    name,
    config,
    ...
  }: {
    options = {
      enable = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = ''
          true: install the package if missing and keep it running. false: stop
          it, leaving it installed. null: leave install and run state alone.
        '';
      };
      package = mkOption {
        type = types.nullOr types.str;
        default = knownServices.${name}.package or null;
        description = "Package Center id; null for features built into DSM.";
      };
      volume = mkOption {
        type = types.str;
        default = "/volume1";
        description = "Volume to install the package on when it's missing.";
      };
      settings = mkOption {
        type = types.attrsOf types.anything;
        default = {};
        description = ''
          Fields for settingsApi's set method, as JSON values. Only these keys
          are compared and set; the rest stay as DSM has them.
        '';
      };
      settingsApi = mkOption {
        type = types.nullOr (types.submodule {
          options = {
            api = mkOption {type = types.str;};
            version = mkOption {type = types.int;};
          };
        });
        default = knownServices.${name}.settingsApi or null;
        description = "The DSM web API whose get/set methods hold this feature's settings.";
      };
    };
    config.settings = lib.mkIf (enableSetting ? ${name} && config.enable != null) {
      ${enableSetting.${name}} = config.enable;
    };
  });

  scheduleType = types.submodule {
    options = {
      weekDays = mkOption {
        type = types.listOf (types.ints.between 0 6);
        default = [0 1 2 3 4 5 6];
        description = "Days to run on, 0 = Sunday.";
      };
      hour = mkOption {type = types.ints.between 0 23;};
      minute = mkOption {type = types.ints.between 0 59;};
      repeatMinutes = mkOption {
        type = types.nullOr (types.enum [1 5 10 15 20 30]);
        default = null;
        description = "Run again every this many minutes, until lastHour.";
      };
      repeatHours = mkOption {
        type = types.nullOr (types.ints.between 1 23);
        default = null;
        description = "Run again every this many hours, until lastHour.";
      };
      lastHour = mkOption {
        type = types.ints.between 0 23;
        default = 23;
        description = "Last hour of the day a repeating task runs.";
      };
    };
  };
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
      description = "Groups that must contain at least `members`; activate only ever adds.";
    };

    homeUsers = mkOption {
      type = types.attrsOf (types.submodule {
        options.uid = mkOption {type = types.int;};
      });
      default = {};
      description = "Users whose systemd user manager runs from boot, for home-manager services.";
    };

    dsm.tasks = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          event = mkOption {
            type = types.enum ["bootup" "shutdown" "schedule"];
            description = "When DSM runs the task: at boot-up, at shutdown, or on `schedule`.";
          };
          schedule = mkOption {
            type = types.nullOr scheduleType;
            default = null;
            description = "When a `schedule` task runs. Only for event = \"schedule\".";
          };
          script = mkOption {
            type = types.str;
            description = "Shell script DSM runs as root.";
          };
          enable = mkOption {
            type = types.bool;
            default = true;
          };
          dependsOn = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Name of a task DSM must run first.";
          };
          notifyOnError = mkOption {
            type = types.bool;
            default = false;
            description = "Have DSM email notifyMail when the script exits non-zero.";
          };
          notifyMail = mkOption {
            type = types.str;
            default = "";
          };
        };
      });
      default = {};
      description = ''
        DSM Task Scheduler script tasks, keyed by task name, run as root.
        activate creates and updates them through DSM's own APIs
        (EventScheduler for boot-up/shutdown, TaskScheduler for scheduled
        ones) and never deletes any, declared before or not.
      '';
    };

    dsm.services = mkOption {
      type = types.attrsOf serviceType;
      default = {};
      description = ''
        DSM features (packages or built-ins) and their settings. Applied at
        deploy, not at boot. Nothing is ever uninstalled, and services, keys
        and packages not declared here are left alone.
      '';
    };

    dsm.packageSources = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Extra Package Center feeds, name -> URL. Added if missing; never removed.";
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
      assertion = name != "Mount nix and start daemon";
      message = "dsm.tasks.\"${name}\": that task mounts /nix and runs activate, so scripts/deploy-potato-bunny.sh owns it.";
    })
    config.dsm.tasks
    ++ lib.mapAttrsToList (name: t: {
      assertion = (t.event == "schedule") == (t.schedule != null);
      message = "dsm.tasks.\"${name}\": `schedule` is required for event = \"schedule\" and only allowed there.";
    })
    config.dsm.tasks
    ++ lib.mapAttrsToList (name: t: {
      assertion = t.schedule == null || t.schedule.repeatMinutes == null || t.schedule.repeatHours == null;
      message = "dsm.tasks.\"${name}\": set repeatMinutes or repeatHours, not both.";
    })
    config.dsm.tasks
    ++ lib.mapAttrsToList (name: s: {
      assertion = s.settings == {} || s.settingsApi != null;
      message = "dsm.services.${name}: settings need a settingsApi to send them to.";
    })
    config.dsm.services
    # Deploys run over ssh.
    ++ lib.optional (config.dsm.services ? ssh) {
      assertion = config.dsm.services.ssh.enable != false && (config.dsm.services.ssh.settings.enable_ssh or true) != false;
      message = "dsm.services.ssh: turning ssh off would lock out deploys, which run over ssh.";
    }
    # DSM's get returns these as [{name, in_use, ...}] while its set takes plain
    # name lists, so a declared value would never match and be re-set on every
    # deploy (and a wrong one could lock ssh out).
    ++ lib.concatMap (key:
      lib.optional (config.dsm.services ? ssh && config.dsm.services.ssh.settings ? ${key}) {
        assertion = false;
        message = "dsm.services.ssh.settings.${key}: not supported; set ssh algorithms in DSM.";
      }) ["ssh_cipher" "ssh_kex" "ssh_mac"]
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

  # A systemd user manager per home user, running from boot. DSM's PAM stack has
  # no pam_systemd, so nothing creates /run/user/<uid> or sets
  # XDG_RUNTIME_DIR; without both, user@<uid>.service exits immediately.
  config.systemd.units = lib.mkMerge (lib.mapAttrsToList (name: u: let
      uid = toString u.uid;
    in {
      # restartIfChanged off: its text changes with every coreutils bump, and a
      # restart propagates to user@<uid> (Requires=) and every user service.
      "user-runtime-dir-${uid}.service" = {
        restartIfChanged = false;
        text = ''
          [Unit]
          Description=Runtime directory for ${name}

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecStart=${pkgs.coreutils}/bin/install -d -m 0700 -o ${uid} -g 100 /run/user/${uid}
        '';
      };
      "user@${uid}.service.d/nix-system.conf".text = ''
        [Unit]
        Requires=user-runtime-dir-${uid}.service
        After=user-runtime-dir-${uid}.service

        [Service]
        Environment=XDG_RUNTIME_DIR=/run/user/${uid}
      '';
    })
    config.homeUsers);
  config.systemd.extraWants."multi-user.target" =
    lib.mapAttrsToList (_: u: "user@${toString u.uid}.service") config.homeUsers;
}
