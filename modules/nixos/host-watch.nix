# Watch another host from this one, and alert if it stops answering.
#
# This exists to close the one hole every self-hosted monitor has: it cannot
# report its own host being down. On this fleet both the Beszel hub and Uptime
# Kuma live on nutmeg — which is the host with a documented history of silent
# hard stops (hosts/nutmeg/crash-diagnostics.nix: three of them, one leaving the
# box dead for 3.5 hours). When nutmeg stops, every agent simply retries forever
# and nobody is told. So the check for nutmeg has to run somewhere that is not
# nutmeg.
#
# Scope, honestly: pantry and nutmeg share a house, a network and a power feed,
# so this catches "nutmeg died" and not "the house lost power". Covering the
# latter needs something off site — one external check would do it — and is
# deliberately not attempted here.
#
# Alerting is by failing the unit, so modules/nixos/notify-failure.nix does the
# actual pushing. That keeps one notification path for the whole fleet rather
# than a second, differently-broken one.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.hostWatch;
in
{
  options.services.hostWatch = {
    enable = lib.mkEnableOption "watching other hosts and alerting when they stop answering";

    targets = lib.mkOption {
      default = { };
      description = "Hosts to watch, keyed by a short name used in the unit name.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            host = lib.mkOption {
              type = lib.types.str;
              description = "Address to probe. Prefer a stable IP over a name — a watcher that fails because DNS is down is a false alarm about the wrong thing.";
            };
            port = lib.mkOption {
              type = lib.types.port;
              default = 22;
              description = "TCP port to connect to. sshd is a good choice: it is up whenever the host is genuinely usable.";
            };
            attempts = lib.mkOption {
              type = lib.types.ints.positive;
              default = 5;
              description = "Consecutive failures required before the unit fails.";
            };
            gapSeconds = lib.mkOption {
              type = lib.types.ints.positive;
              default = 30;
              description = ''
                Seconds between attempts. attempts × gapSeconds is how long the
                target may be unreachable before you are told; it wants to be
                comfortably longer than a reboot, or every deploy pages you.
              '';
            };
            onCalendar = lib.mkOption {
              type = lib.types.str;
              default = "*:0/5";
              description = "How often to run the check.";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.mapAttrs' (
      name: t:
      lib.nameValuePair "host-watch-${name}" {
        description = "Check ${name} (${t.host}:${toString t.port}) is answering";
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
        script = ''
          set -uo pipefail
          # Retry rather than alerting on the first miss. A single failed
          # connect means almost nothing: the target could be mid-reboot, mid
          # deploy, or the network could have hiccuped. Requiring
          # ${toString t.attempts} consecutive failures over
          # ${toString (t.attempts * t.gapSeconds)}s is what separates "it is
          # gone" from "it blinked", and false alarms are how alerting dies.
          for i in $(${pkgs.coreutils}/bin/seq ${toString t.attempts}); do
            if ${pkgs.netcat}/bin/nc -z -w 5 ${t.host} ${toString t.port} 2>/dev/null; then
              [ "$i" = "1" ] || echo "${name}: answered on attempt $i"
              exit 0
            fi
            echo "${name}: no answer on ${t.host}:${toString t.port} (attempt $i/${toString t.attempts})" >&2
            [ "$i" = "${toString t.attempts}" ] || ${pkgs.coreutils}/bin/sleep ${toString t.gapSeconds}
          done
          echo "${name} is DOWN: no TCP answer on ${t.host}:${toString t.port} after ${toString t.attempts} attempts over ${toString (t.attempts * t.gapSeconds)}s" >&2
          exit 1
        '';
      }
    ) cfg.targets;

    systemd.timers = lib.mapAttrs' (
      name: t:
      lib.nameValuePair "host-watch-${name}" {
        description = "Periodic reachability check for ${name}";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = t.onCalendar;
          # Deliberately NOT Persistent: a missed check is not worth replaying
          # after the fact. If THIS host was down, the answer to "was nutmeg up
          # 40 minutes ago" is neither knowable nor actionable now.
          Persistent = false;
          RandomizedDelaySec = "30s";
        };
      }
    ) cfg.targets;

    services.notifyFailure.units = map (n: "host-watch-${n}.service") (lib.attrNames cfg.targets);
  };
}
