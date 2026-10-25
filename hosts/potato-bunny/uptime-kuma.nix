# Uptime Kuma: the dead-man's switch for timer-driven jobs. Each job listed in
# a host's services.unitHeartbeat.units (modules/nixos/unit-heartbeat.nix)
# pings a Push monitor here when it succeeds, and Kuma alerts when a ping is
# overdue. On the NAS rather than a host it watches, so it keeps alerting when
# nutmeg is down.
#
#   https://status.vaquita-woodpecker.ts.net   (tsnsrv.nix, the web UI)
#   http://[<this host's tailnet ULA>]:3010    (heartbeat pushes)
#     -> uptime-kuma, data in /volume2/@appdata/uptime-kuma
#
# Pushes come straight to the tailnet address, not the ts.net name: nutmeg
# runs --accept-dns=false and can't resolve MagicDNS names. Kuma listens on
# every address for that, so the LAN reaches it too.
#
# ── How the monitors get created ──────────────────────────────────────────
#
# Uptime Kuma has no declarative config: monitors live in a SQLite DB behind a
# Vue SPA whose only API is Socket.io. So the unit's pre-start writes the
# monitor rows into that DB directly, before Kuma starts and reads them.
#
# Driving the web UI instead sounds like the "supported" path and is not: it
# binds you to CSS selectors upstream changes silently and without migration
# (the monitor-type control is `#type`, not the documented `#monitor-type`),
# and the Push URL field is rendered *disabled*, so the token cannot be chosen
# from the UI at all. The schema is versioned by knex migrations and fails
# loudly, which is the better thing to depend on.
#
# Choosing the token is the real prize: it is just the unit name, so the URL a
# unit pings is derivable from its own name. No generated token map, no state
# file, nothing to keep in sync.
#
# The sync runs with Kuma STOPPED (ExecStartPre). Kuma caches monitors in
# memory, so a write to a live DB appears to succeed and then does nothing
# until the next restart. The desired set is embedded in the sync script, so
# the unit changes, and restarts, whenever any host's list does.
#
# Monitors are only added and updated, never deleted: a unit dropped from a
# list leaves its monitor behind, to pause or delete in the UI.
#
# RISK, stated plainly: this writes into a schema another application owns. If a
# future Kuma release changes the `monitor` table, this breaks — but it breaks
# as a failed start with a SQL error, not silently, and notify-failure reports
# it.
{
  config,
  lib,
  pkgs,
  flake,
  ...
}: let
  data = "/volume2/@appdata/uptime-kuma";
  db = "${data}/kuma.db";

  # Every NixOS host's heartbeat units. A host without the module (or with it
  # off) contributes nothing.
  hostUnits = lib.concatMap (
    host: let
      hb = host.config.services.unitHeartbeat or {enable = false;};
    in
      lib.optionals hb.enable hb.units
  ) (lib.attrValues flake.nixosConfigurations);

  units = hostUnits ++ config.uptimeKuma.localHeartbeats;
  unitName = u: lib.removeSuffix ".service" u;
  names = map (u: unitName u.unit) units;
  duplicates = lib.unique (lib.filter (n: lib.count (m: m == n) names > 1) names);

  sqlStr = s: "'" + lib.replaceStrings ["'"] ["''"] s + "'";
  # One idempotent upsert per unit. INSERT ... WHERE NOT EXISTS rather than
  # INSERT OR REPLACE: replace would rewrite the primary key and orphan every
  # heartbeat row that references this monitor, silently wiping its history.
  desiredSql =
    lib.concatMapStrings (
      u: let
        n = unitName u.unit;
        i = toString u.interval;
      in ''
        INSERT INTO monitor (name, type, push_token, interval, retry_interval, user_id, active)
          SELECT ${sqlStr n}, 'push', ${sqlStr n}, ${i}, ${i},
                 (SELECT id FROM user ORDER BY id LIMIT 1), 1
          WHERE NOT EXISTS (SELECT 1 FROM monitor WHERE name = ${sqlStr n});
        UPDATE monitor SET type = 'push', push_token = ${sqlStr n},
               interval = ${i}, retry_interval = ${i}, active = 1
          WHERE name = ${sqlStr n};
      ''
    )
    units;

  sync = pkgs.writeShellScript "uptime-kuma-monitor-sync" ''
    set -euo pipefail
    sql() { ${pkgs.util-linux}/bin/setpriv --reuid=svc-uptime-kuma --regid=users --init-groups -- ${pkgs.sqlite}/bin/sqlite3 ${db} "$@"; }

    # Kuma creates the DB and runs its migrations on first start; until then
    # there is nothing to sync into, and the next restart will do it.
    if [ ! -f ${db} ] || ! sql "SELECT 1 FROM sqlite_master WHERE type='table' AND name='monitor';" | ${pkgs.gnugrep}/bin/grep -q 1; then
      echo "uptime-kuma-monitor-sync: no monitor table yet; skipping until Kuma has created its database" >&2
      exit 0
    fi
    if [ "$(sql 'SELECT count(*) FROM user;')" = "0" ]; then
      # Monitors are owned by a user row; without one Kuma shows nothing. The
      # admin account is created once through the web UI (or
      # `KUMA_URL=http://[<ULA>]:3010 sudo nix run .#provision-uptime-kuma`
      # from nutmeg, which holds the credentials); restart this unit afterwards.
      echo "uptime-kuma-monitor-sync: no admin account yet; skipping" >&2
      exit 0
    fi
    sql <<'SQL'
    BEGIN;
    ${desiredSql}
    COMMIT;
    SQL
    echo "uptime-kuma-monitor-sync: ${toString (builtins.length units)} push monitors in place"
  '';
in {
  # Jobs on this NAS that ping their own Push monitor at 127.0.0.1:3010.
  options.uptimeKuma.localHeartbeats = lib.mkOption {
    default = [];
    description = "Units on this host with a Push monitor, as {unit, interval} like services.unitHeartbeat.units.";
    type = lib.types.listOf (lib.types.submodule {
      options = {
        unit = lib.mkOption {type = lib.types.str;};
        interval = lib.mkOption {type = lib.types.ints.positive;};
      };
    });
  };

  config = {
    assertions = [
      {
        assertion = duplicates == [];
        message = "uptime-kuma: heartbeat unit(s) listed by more than one host share a push token: ${lib.concatStringsSep ", " duplicates}";
      }
    ];

    users.users.svc-uptime-kuma.description = "Uptime Kuma";

    tsnsrv.services.status.upstream = "http://127.0.0.1:3010";

    appdataBackup.jobs.uptime-kuma.sqlite = ["kuma.db"];

    systemd.units."uptime-kuma.service".text = ''
      [Unit]
      Description=Uptime Kuma
      ConditionPathIsMountPoint=/volume2
      OnFailure=notify-failure@%n.service
      After=network-online.target
      Wants=network-online.target

      [Service]
      User=svc-uptime-kuma
      PermissionsStartOnly=true
      ExecStartPre=${pkgs.coreutils}/bin/install -d -o svc-uptime-kuma -m 0750 ${data}
      # Owns everything in its data dir, as StateDirectory= would.
      ExecStartPre=${pkgs.coreutils}/bin/chown -R svc-uptime-kuma ${data}
      ExecStartPre=${sync}
      Environment=DATA_DIR=${data}/
      Environment=HOST=::
      Environment=PORT=3010
      Environment=NODE_ENV=production
      Environment=UPTIME_KUMA_DB_TYPE=sqlite
      ExecStart=${pkgs.uptime-kuma}/bin/uptime-kuma-server
      Restart=on-failure
      RestartSec=5
    '';
  };
}
