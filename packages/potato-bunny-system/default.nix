# The potato-bunny system layer: a generation is one store path holding
# everything `activate` installs on the NAS.
#
#   etc/<path>              files for /etc (only /etc/nix is allowed)
#   units/<name>            systemd units and drop-ins
#   wants/<target>/<name>   empty markers; activate links <target>.wants/<name>
#   users.json              {"users": {...}, "groups": {name: [members]}}
#   dsm-tasks.json          DSM Task Scheduler tasks (boot-up, shutdown, scheduled)
#   dsm-services.json       DSM packages and feature settings (dsm.services)
#   dsm-feeds.json          extra Package Center feeds, name -> URL
#   restart-exempt          units not restarted when they change
#   default-profile         the root default profile (Lix + extras), if nix.package is set
#   bin/activate            applies all of the above; see activate.sh
#
# Built with lib.evalModules over ./options.nix rather than NixOS or
# system-manager: DSM owns the rest of the machine, so the layer only
# describes the handful of things it manages.
{
  pkgs,
  perSystem,
  flake,
  ...
}: let
  inherit (pkgs) lib;

  activateScript = pkgs.writeShellApplication {
    name = "potato-bunny-activate";
    runtimeInputs = [pkgs.coreutils pkgs.findutils pkgs.gnused pkgs.gnugrep pkgs.jq pkgs.diffutils pkgs.util-linux];
    text = builtins.readFile ./dsm.sh + builtins.readFile ./activate.sh;
  };

  mkGeneration = modules: let
    evaluated = lib.evalModules {
      modules = [./options.nix] ++ modules;
      specialArgs = {inherit pkgs perSystem;};
    };
    cfg = evaluated.config;

    failed = lib.filter (a: !a.assertion) cfg.assertions;
    checked =
      if failed == []
      then cfg
      else throw "potato-bunny-system:\n${lib.concatMapStringsSep "\n" (a: "- ${a.message}") failed}";

    etcFiles =
      lib.mapAttrsToList (path: f: {
        inherit path;
        src = pkgs.writeText (baseNameOf path) f.text;
      })
      checked.environment.etc;

    units =
      lib.mapAttrsToList (name: u: {
        inherit name;
        src = pkgs.writeText (lib.replaceStrings ["@"] ["-at-"] (baseNameOf name)) u.text;
      })
      checked.systemd.units;

    wants =
      lib.concatLists (lib.mapAttrsToList (name: u: map (target: {inherit target name;}) u.wantedBy) checked.systemd.units)
      ++ lib.concatLists (lib.mapAttrsToList (target: names: map (name: {inherit target name;}) names) checked.systemd.extraWants);

    usersJson = pkgs.writeText "users.json" (builtins.toJSON {
      users = checked.users.users;
      groups = lib.mapAttrs (_: g: g.members) checked.users.groups;
    });

    dsmTasksJson = pkgs.writeText "dsm-tasks.json" (builtins.toJSON checked.dsm.tasks);
    dsmServicesJson = pkgs.writeText "dsm-services.json" (builtins.toJSON checked.dsm.services);
    dsmFeedsJson = pkgs.writeText "dsm-feeds.json" (builtins.toJSON checked.dsm.packageSources);

    restartExempt = lib.attrNames (lib.filterAttrs (_: u: !u.restartIfChanged) checked.systemd.units);

    defaultProfile =
      if checked.nix.package == null
      then null
      else
        pkgs.buildEnv {
          name = "potato-bunny-default-profile";
          paths = [checked.nix.package] ++ checked.profileExtra;
        };
  in
    pkgs.runCommand "potato-bunny-system" {passthru.config = checked;} ''
      mkdir -p $out/etc $out/units $out/wants $out/bin
      ${lib.concatMapStrings (f: ''
          install -D -m 0644 ${f.src} "$out/etc/${f.path}"
        '')
        etcFiles}
      ${lib.concatMapStrings (u: ''
          install -D -m 0644 ${u.src} "$out/units/${u.name}"
        '')
        units}
      ${lib.concatMapStrings (w: ''
          mkdir -p "$out/wants/${w.target}"
          touch "$out/wants/${w.target}/${w.name}"
        '')
        wants}
      cp ${usersJson} $out/users.json
      cp ${dsmTasksJson} $out/dsm-tasks.json
      cp ${dsmServicesJson} $out/dsm-services.json
      cp ${dsmFeedsJson} $out/dsm-feeds.json
      printf '%s\n' ${lib.escapeShellArgs restartExempt} | sed '/^$/d' > $out/restart-exempt
      ${lib.optionalString (defaultProfile != null) "ln -s ${defaultProfile} $out/default-profile"}
      # The generation's own nix-env, since neither sudo's secure_path nor the
      # DSM Task Scheduler has nix on PATH.
      cat > $out/bin/activate <<EOF
      #!${pkgs.runtimeShell}
      if [ -z "\''${NIX_ENV:-}" ] && [ -x $out/default-profile/bin/nix-env ]; then
        export NIX_ENV=$out/default-profile/bin/nix-env
      fi
      exec ${lib.getExe activateScript} --generation $out "\$@"
      EOF
      chmod +x $out/bin/activate
    '';

  hostGeneration = mkGeneration [../../hosts/potato-bunny/system.nix];

  tests = import ./tests.nix {
    inherit pkgs mkGeneration hostGeneration;
    hawkenHome = flake.legacyPackages.x86_64-linux.homeConfigurations."hawken@potato-bunny".activationPackage;
  };
in
  hostGeneration.overrideAttrs (old: {
    passthru = old.passthru // {inherit tests mkGeneration;};
    meta.platforms = ["x86_64-linux"];
  })
