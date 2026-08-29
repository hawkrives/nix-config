# Dead-man's-switch heartbeats: ping an Uptime Kuma Push monitor when a unit
# SUCCEEDS, so that the *absence* of a ping is what raises the alarm.
#
# This is the other half of modules/nixos/notify-failure.nix, and it exists
# because OnFailure has two blind spots that have both actually bitten:
#
#   * A unit that succeeds while doing nothing. arr-backup-pin exited 0 for a
#     day with all four of its API calls failing. OnFailure never fired.
#   * A timer that stops firing at all. Nothing fails, so nothing notifies.
#
# Both are silence that looks like success, and only absence-detection catches
# them.
#
# MECHANISM: systemd's OnSuccess=, not ExecStartPost. ExecStartPost is wrong
# here — for a Type=simple unit it runs the moment the main process is forked,
# so it would report "started", not "succeeded". OnSuccess= fires only on
# genuine successful completion, for every service type.
#
# ── How the monitors get created ──────────────────────────────────────────
#
# Uptime Kuma has no declarative config: monitors live in a SQLite DB behind a
# Vue SPA whose only API is Socket.io. So this module writes the monitor rows
# into that DB directly and restarts Kuma to pick them up.
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
# The sync runs with Kuma STOPPED. Kuma caches monitors in memory, so a write to
# a live DB appears to succeed and then does nothing until the next restart.
#
# RISK, stated plainly: this writes into a schema another application owns. If a
# future Kuma release changes the `monitor` table, this breaks — but it breaks
# as a failed unit with a SQL error, not silently, and notifyFailure reports it.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.unitHeartbeat;

  unitName = u: lib.removeSuffix ".service" u;

  # The push token IS the unit name. `monitor.push_token` is varchar(32), and
  # SQLite does not enforce that, so an over-long name would be stored fine and
  # then mismatch anything that does enforce it. Catch it at eval instead.
  tooLong = lib.filter (u: lib.stringLength (unitName u.unit) > 32) cfg.units;

  sqlStr = s: "'" + lib.replaceStrings [ "'" ] [ "''" ] s + "'";

  # One idempotent upsert per unit. INSERT ... WHERE NOT EXISTS rather than
  # INSERT OR REPLACE: replace would rewrite the primary key and orphan every
  # heartbeat row that references this monitor, silently wiping its history.
  desiredSql = lib.concatMapStrings (
    u:
    let
      n = unitName u.unit;
      i = toString u.interval;
    in
    ''
      INSERT INTO monitor (name, type, push_token, interval, retry_interval, user_id, active)
        SELECT ${sqlStr n}, 'push', ${sqlStr n}, ${i}, ${i},
               (SELECT id FROM user ORDER BY id LIMIT 1), 1
        WHERE NOT EXISTS (SELECT 1 FROM monitor WHERE name = ${sqlStr n});
      UPDATE monitor SET type = 'push', push_token = ${sqlStr n},
             interval = ${i}, retry_interval = ${i}, active = 1
        WHERE name = ${sqlStr n};
    ''
  ) cfg.units;

  # Normalised snapshot of what we care about, so the sync can tell "already
  # correct" from "needs a restart" without diffing 116 columns.
  # NB: the placeholder is '-' rather than the obvious empty string. Two
  # apostrophes in a row terminate a Nix indented string, so COALESCE(x,'')
  # would end this expression mid-SQL. '-' can never collide with a real token,
  # since tokens here are always unit names.
  stateQuery = ''
    SELECT name || '|' || COALESCE(push_token,'-') || '|' || interval || '|' || active
      FROM monitor WHERE type = 'push' ORDER BY name;
  '';

  desiredState = lib.concatMapStrings (
    u: "${unitName u.unit}|${unitName u.unit}|${toString u.interval}|1\n"
  ) cfg.units;
in
{
  options.services.unitHeartbeat = {
    enable = lib.mkEnableOption "success heartbeats to an Uptime Kuma push monitor";

    baseUrl = lib.mkOption {
      type = lib.types.str;
      example = "http://127.0.0.1:3010";
      description = "Base URL of the Uptime Kuma instance, no trailing slash.";
    };

    database = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/private/uptime-kuma/kuma.db";
      description = ''
        Kuma's SQLite database. The default is the DynamicUser StateDirectory
        path — /var/lib/uptime-kuma is a symlink into /var/lib/private, and
        sqlite needs to create -wal/-shm siblings, so name the real location.
      '';
    };

    units = lib.mkOption {
      default = [ ];
      description = ''
        Units to heartbeat on success, each with the interval Kuma should expect
        a ping within.

        Only meaningful for units that *complete* — timer-driven oneshots. A
        long-running daemon never "succeeds" while healthy, so listing one gets
        you a heartbeat at startup and then silence, i.e. a guaranteed false
        alarm. Use an ordinary HTTP/TCP monitor for those instead.
      '';
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            unit = lib.mkOption {
              type = lib.types.str;
              description = "Unit name, including the `.service` suffix.";
            };
            interval = lib.mkOption {
              type = lib.types.ints.positive;
              description = ''
                Seconds Kuma waits for a ping before calling the monitor down.
                Must exceed the unit's worst-case gap between runs, INCLUDING
                its timer's RandomizedDelaySec — a daily job with an hour of
                jitter can legitimately go 25h between successes, so anything
                at or under 86400 would alert on a perfectly healthy job.
              '';
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = tooLong == [ ];
            message =
              "unitHeartbeat: unit name(s) longer than monitor.push_token's 32 chars: "
              + lib.concatMapStringsSep ", " (u: unitName u.unit) tooLong;
          }
        ];

        # ── Monitor sync ──────────────────────────────────────────────────
        # Ordered after Kuma so that on a first-ever boot the DB and its schema
        # already exist (Kuma runs its knex migrations at startup). It then
        # stops Kuma to write, and starts it again — see the header for why a
        # live write is not enough.
        systemd.services.uptime-kuma-monitor-sync = {
          description = "Sync Uptime Kuma push monitors from the NixOS config";
          after = [ "uptime-kuma.service" ];
          wants = [ "uptime-kuma.service" ];
          wantedBy = [ "multi-user.target" ];
          # The desired set is embedded in the script below, so this unit's
          # definition changes whenever the config does — which is what makes
          # it re-run on deploy rather than only at boot.
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [
            pkgs.sqlite
            pkgs.systemd
            pkgs.coreutils
          ];
          script = ''
            set -euo pipefail
            db=${lib.escapeShellArg cfg.database}

            # Kuma creates the DB and runs its migrations on first start; give
            # it a chance rather than failing a fresh install's first boot.
            for _ in $(seq 60); do
              [ -f "$db" ] && sqlite3 "$db" \
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='monitor';" \
                | grep -q 1 && break
              sleep 2
            done
            if ! sqlite3 "$db" "SELECT 1 FROM sqlite_master WHERE type='table' AND name='monitor';" | grep -q 1; then
              echo "uptime-kuma-monitor-sync: no monitor table at $db; is uptime-kuma running?" >&2
              exit 1
            fi

            if [ "$(sqlite3 "$db" 'SELECT count(*) FROM user;')" = "0" ]; then
              # Monitors are owned by a user row; without one Kuma shows nothing
              # and the whole sync is pointless. The admin account is created
              # once through the web UI (or `nix run .#provision-uptime-kuma`).
              echo "uptime-kuma-monitor-sync: no admin account yet — create one, then re-run this unit" >&2
              exit 1
            fi

            want=${lib.escapeShellArg desiredState}
            have=$(sqlite3 "$db" ${lib.escapeShellArg stateQuery})

            if [ "$(printf '%s' "$want" | sort)" = "$(printf '%s\n' "$have" | sort)" ]; then
              echo "uptime-kuma-monitor-sync: ${toString (builtins.length cfg.units)} monitors already correct"
              exit 0
            fi

            echo "uptime-kuma-monitor-sync: applying changes (kuma will restart)"
            # Stop first: Kuma holds monitors in memory and would both ignore
            # these rows and potentially write its cached copy back over them.
            systemctl stop uptime-kuma.service
            sqlite3 "$db" <<'SQL'
            BEGIN;
            ${desiredSql}
            COMMIT;
            SQL
            systemctl start uptime-kuma.service
            echo "uptime-kuma-monitor-sync: synced ${toString (builtins.length cfg.units)} monitors"
          '';
        };

        systemd.services."unit-heartbeat@" = {
          description = "Heartbeat %i to Uptime Kuma";
          serviceConfig = {
            Type = "oneshot";
            DynamicUser = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
          };
          scriptArgs = "%i";
          script = ''
            set -uo pipefail
            # The push token is the unit name, so there is nothing to look up.
            # --fail so a 404 (monitor missing) shows in the journal rather than
            # silently counting as a delivered heartbeat. Exit 0 regardless: an
            # undeliverable heartbeat must never turn a successful backup into a
            # failed unit — the missed ping is itself the signal, and Kuma
            # raises it.
            if ! ${pkgs.curl}/bin/curl -fsS --max-time 20 \
                 "${cfg.baseUrl}/api/push/$1?status=up&msg=OK" >/dev/null; then
              echo "unit-heartbeat: push failed for '$1' (monitor missing? kuma down?)" >&2
            fi
            exit 0
          '';
        };
      }

      {
        systemd.services = lib.listToAttrs (
          map (
            u: lib.nameValuePair (unitName u.unit) {
              onSuccess = [ "unit-heartbeat@${unitName u.unit}.service" ];
            }
          ) cfg.units
        );
      }
    ]
  );
}
