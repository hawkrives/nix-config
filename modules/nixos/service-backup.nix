# Reusable app-aware backup of service state to the NAS. For each job it takes a
# transactionally-consistent `sqlite3 .backup` snapshot of the live databases
# (no downtime) and rsyncs the rest of the config, then mirrors the result to
# ${dest}/<job>/. Runs as root so it can read DynamicUser /var/lib/private dirs.
#
# Each job is its own systemd service and timer — `service-backup-<job>` — rather
# than one unit running every job in sequence. That buys three things the single
# unit could not:
#
#   * failures are attributable. `systemctl` shows which service last succeeded
#     and when, and a broken job is a failed unit rather than a line in a long log.
#   * jobs are independent. One slow job (plex, ~12 of the ~14 minutes the old
#     serial run took) no longer delays everything behind it.
#   * schedules are per job, so a cheap job can run more often than an expensive one.
#
# A missing source is an **error**, not a warning. The old module logged
# `WARN: ... not found` and still exited 0, so a path that drifted out from under
# a job — as jellyfin's library.db did when 10.11 consolidated it away — produced
# a passing run forever. Set `optional = true` on a job whose paths legitimately
# come and go.
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
      optional = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Tolerate missing sources. By default a declared path or database that
          does not exist fails the job, so drift is visible; set this for a job
          whose files are genuinely sometimes absent.
        '';
      };
      schedule = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "systemd OnCalendar for this job. Null uses services.serviceBackup.schedule.";
      };
    };
  };

  mkScript = name: job:
    let
      dest = "${cfg.dest}/${name}";
      src = "${job.root}/${job.path}";
      excludeArgs = lib.concatMapStringsSep " " (e: "--exclude=${lib.escapeShellArg e}")
        ([ "*.db" "*.db-wal" "*.db-shm" "*.db-journal" ] ++ job.excludes);

      # Missing sources either fail the job or are noted and skipped.
      missing = what: path:
        if job.optional then
          ''echo "note: ${name}: ${what} absent, skipping (optional): ${path}"''
        else
          ''{ echo "ERROR: ${name}: ${what} not found: ${path}" >&2; fail=1; }'';

      sqliteCmds = lib.concatMapStringsSep "\n" (db: ''
        if [ -f ${lib.escapeShellArg "${job.root}/${db}"} ]; then
          sqlite3 ${lib.escapeShellArg "${job.root}/${db}"} ".backup '${dest}/${baseNameOf db}'" \
            || { echo "ERROR: ${name}: sqlite snapshot failed: ${db}" >&2; fail=1; }
        else
          ${missing "database" "${job.root}/${db}"}
        fi
      '') job.sqlite;
    in ''
      set -uo pipefail
      fail=0
      mkdir -p ${lib.escapeShellArg dest}

      if [ -e ${lib.escapeShellArg src} ]; then
        rsync -a --delete ${excludeArgs} \
          ${lib.escapeShellArg src} ${lib.escapeShellArg "${dest}/"} \
          || { echo "ERROR: ${name}: rsync failed" >&2; fail=1; }
      else
        ${missing "path" src}
      fi

      ${sqliteCmds}

      exit "$fail"
    '';

  unitName = name: "service-backup-${name}";
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
      description = "Default systemd OnCalendar expression; a job may override it.";
    };
    randomizedDelaySec = lib.mkOption {
      type = lib.types.str;
      default = "1h";
      description = ''
        Spread each job's start over this window. Without it every job would fire
        at once now that they no longer queue behind one another.
      '';
    };
    jobs = lib.mkOption {
      type = lib.types.attrsOf jobModule;
      default = { };
      description = "Backup jobs, keyed by service name.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.mapAttrs' (name: job:
      lib.nameValuePair (unitName name) {
        description = "Back up ${name} state to the NAS";
        path = [ pkgs.rsync pkgs.sqlite pkgs.coreutils ];
        serviceConfig.Type = "oneshot";
        script = mkScript name job;
      }) cfg.jobs;

    systemd.timers = lib.mapAttrs' (name: job:
      lib.nameValuePair (unitName name) {
        description = "Scheduled backup of ${name} state to the NAS";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = if job.schedule != null then job.schedule else cfg.schedule;
          Persistent = true;
          RandomizedDelaySec = cfg.randomizedDelaySec;
        };
      }) cfg.jobs;

    # `systemctl start service-backup.target` runs every job at once, which is
    # what the old single unit gave you for free. Nothing pulls this in on a
    # timer — the per-job timers do the scheduling.
    systemd.targets.service-backup = {
      description = "All app-aware state backups";
      wants = map (name: "${unitName name}.service") (lib.attrNames cfg.jobs);
    };
  };
}
