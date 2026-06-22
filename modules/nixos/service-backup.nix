# Reusable app-aware backup of service state to the NAS. For each job it takes a
# transactionally-consistent `sqlite3 .backup` snapshot of the live databases
# (no downtime) and rsyncs the rest of the config, then mirrors the result to
# ${dest}/<job>/. Runs as root so it can read DynamicUser /var/lib/private dirs.
{ lib, config, pkgs, ... }:
let
  cfg = config.services.serviceBackup;

  jobModule = lib.types.submodule {
    options = {
      root = lib.mkOption {
        type = lib.types.str;
        description = "Base directory of the service's state.";
      };
      sqlite = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Database files (relative to root) to snapshot consistently.";
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = ".";
        description = "Single path (relative to root) to rsync. '.' means the whole root.";
      };
      excludes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra rsync excludes (on top of the always-excluded *.db*).";
      };
    };
  };

  mkJob = name: job:
    let
      dest = "${cfg.dest}/${name}";
      excludeArgs = lib.concatMapStringsSep " " (e: "--exclude=${lib.escapeShellArg e}")
        ([ "*.db" "*.db-wal" "*.db-shm" "*.db-journal" ] ++ job.excludes);
      sqliteCmds = lib.concatMapStringsSep "\n" (db: ''
        if [ -f ${lib.escapeShellArg "${job.root}/${db}"} ]; then
          sqlite3 ${lib.escapeShellArg "${job.root}/${db}"} ".backup '${dest}/${baseNameOf db}'" \
            || { echo "WARN: sqlite snapshot failed: ${name}/${db}" >&2; fail=1; }
        else
          echo "WARN: ${name}: db not found: ${job.root}/${db}" >&2
        fi
      '') job.sqlite;
    in ''
      echo "=== ${name} ==="
      mkdir -p ${lib.escapeShellArg dest}
      if [ -e ${lib.escapeShellArg "${job.root}/${job.path}"} ]; then
        rsync -a --delete ${excludeArgs} \
          ${lib.escapeShellArg "${job.root}/${job.path}"} ${lib.escapeShellArg "${dest}/"} \
          || { echo "WARN: rsync failed: ${name}" >&2; fail=1; }
      else
        echo "WARN: ${name}: path not found: ${job.root}/${job.path}" >&2
      fi
      ${sqliteCmds}
    '';
in
{
  options.services.serviceBackup = {
    enable = lib.mkEnableOption "app-aware service-state backups to the NAS";
    dest = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/servarr/backups/${config.networking.hostName}";
      description = "Destination root; one subdir per job.";
    };
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "systemd OnCalendar expression.";
    };
    jobs = lib.mkOption {
      type = lib.types.attrsOf jobModule;
      default = { };
      description = "Backup jobs, keyed by service name.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.service-backup = {
      description = "App-aware backup of service state to the NAS";
      path = [ pkgs.rsync pkgs.sqlite pkgs.coreutils ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -uo pipefail
        fail=0
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList mkJob cfg.jobs)}
        exit "$fail"
      '';
    };

    systemd.timers.service-backup = {
      description = "Daily app-aware backup of service state to the NAS";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
      };
    };
  };
}
