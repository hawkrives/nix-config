# Nightly copies of the Nix-run services' state from /volume2/@appdata (the
# SSD volume) to /volume1/app-servarr/backups/potato-bunny (the HDD array), so
# a lost volume2 doesn't take them with it. A shared folder, unlike @appdata,
# so Hyper Backup can include it.
#
# SQLite databases are copied with `.backup`, which is consistent while the
# service keeps writing. It runs as the database's owner: a root sqlite3 on a
# live WAL database can leave root-owned -wal/-shm files the service can't
# open. Everything in `files` is copied as is.
#
# appdataBackup.jobs.<name> = { sqlite = [...]; files = [...]; } with paths
# relative to /volume2/@appdata/<name>.
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types;
  src = "/volume2/@appdata";
  dest = "/volume1/app-servarr/backups/potato-bunny";
  jobs = config.appdataBackup.jobs;

  script = pkgs.writeShellScript "appdata-backup" ''
    set -euo pipefail
    PATH=${lib.makeBinPath [pkgs.coreutils pkgs.sqlite pkgs.curl pkgs.util-linux]}
    as_owner() { setpriv --reuid="$(stat -c %u "$1")" --regid=users --clear-groups -- "''${@:2}"; }
    ${lib.concatStrings (lib.mapAttrsToList (name: job: ''
        mkdir -p -m 0700 ${dest}/${name}
        chown "$(stat -c %u ${src}/${name})" ${dest}/${name}
        ${lib.concatMapStrings (f: ''
            as_owner ${src}/${name}/${f} mkdir -p "$(dirname ${dest}/${name}/${f})"
            as_owner ${src}/${name}/${f} sqlite3 ${src}/${name}/${f} ".backup '${dest}/${name}/${f}.tmp'"
            mv ${dest}/${name}/${f}.tmp ${dest}/${name}/${f}
          '')
          job.sqlite}
        ${lib.concatMapStrings (f: ''
            mkdir -p "$(dirname ${dest}/${name}/${f})"
            cp -p ${src}/${name}/${f} ${dest}/${name}/${f}
          '')
          job.files}
        echo "appdata-backup: ${name} done"
      '')
      jobs)}
    # The heartbeat: Uptime Kuma alerts if this stops arriving (uptime-kuma.nix).
    curl -fsS --max-time 20 "http://127.0.0.1:3010/api/push/appdata-backup?status=up&msg=OK" >/dev/null ||
      echo "appdata-backup: heartbeat push failed" >&2
  '';
in {
  options.appdataBackup.jobs = mkOption {
    default = {};
    description = "Service state under /volume2/@appdata/<name> to copy nightly.";
    type = types.attrsOf (types.submodule {
      options = {
        sqlite = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "SQLite databases, copied with .backup.";
        };
        files = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Other files, copied as they are.";
        };
      };
    });
  };

  config = {
    uptimeKuma.localHeartbeats = [
      {
        unit = "appdata-backup.service";
        interval = 90000; # daily, no jitter
      }
    ];

    systemd.units."appdata-backup.service" = {
      wantedBy = [];
      text = ''
        [Unit]
        Description=Copy Nix-run service state to volume1
        ConditionPathIsMountPoint=/volume2
        OnFailure=notify-failure@%n.service
        RequiresMountsFor=/volume1 /volume2

        [Service]
        Type=oneshot
        ExecStart=${script}
      '';
    };
    systemd.units."appdata-backup.timer" = {
      wantedBy = ["timers.target"];
      text = ''
        [Unit]
        Description=Copy Nix-run service state to volume1, nightly

        [Timer]
        OnCalendar=*-*-* 03:15
        Persistent=true
      '';
    };
  };
}
