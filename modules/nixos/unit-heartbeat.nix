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
# The matching Push monitors are written into Kuma by its unit on potato-bunny,
# from every NixOS host's `units` list (hosts/potato-bunny/uptime-kuma.nix),
# when potato-bunny is deployed. So after adding a unit here, deploy
# potato-bunny too (`mise run potato-bunny:ask`): until then the unit's pings
# go to a monitor that doesn't exist, and Kuma can't alert on its silence.
# The push token is the unit name, so the URL a unit pings is derivable from
# its own name.
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.services.unitHeartbeat;

  unitName = u: lib.removeSuffix ".service" u;

  # The push token IS the unit name. `monitor.push_token` is varchar(32), and
  # SQLite does not enforce that, so an over-long name would be stored fine and
  # then mismatch anything that does enforce it. Catch it at eval instead.
  tooLong = lib.filter (u: lib.stringLength (unitName u.unit) > 32) cfg.units;
in {
  options.services.unitHeartbeat = {
    enable = lib.mkEnableOption "success heartbeats to an Uptime Kuma push monitor";

    baseUrl = lib.mkOption {
      type = lib.types.str;
      example = "http://[fd7a:115c:a1e0:ab12:4843:cd96:626f:fb9c]:3010";
      description = "Base URL of the Uptime Kuma instance, no trailing slash.";
    };

    units = lib.mkOption {
      default = [];
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
            assertion = tooLong == [];
            message =
              "unitHeartbeat: unit name(s) longer than monitor.push_token's 32 chars: "
              + lib.concatMapStringsSep ", " (u: unitName u.unit) tooLong;
          }
        ];

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
            u:
              lib.nameValuePair (unitName u.unit) {
                onSuccess = ["unit-heartbeat@${unitName u.unit}.service"];
              }
          )
          cfg.units
        );
      }
    ]
  );
}
