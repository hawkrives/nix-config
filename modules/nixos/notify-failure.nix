# Push a Telegram message when a systemd unit fails.
#
# Usage: list units in `services.notifyFailure.units` and this stamps
# `OnFailure=notify-failure@<unit>.service` onto each. The template unit is
# always defined (so `systemctl start notify-failure@test.service` works for a
# smoke test) but sends nothing unless a token file is configured.
#
# WHAT THIS DOES NOT CATCH, deliberately stated so it isn't mistaken for
# complete coverage:
#
#   * A unit that SUCCEEDS while doing nothing. arr-backup-pin exited 0 for a
#     day while every one of its four API calls failed; OnFailure would not
#     have fired once. That class is fixed in the unit itself (make the failure
#     a non-zero exit), not here.
#   * A timer that stops firing altogether. No unit fails, so nothing notifies.
#     Catching that needs a dead-man's-switch (a ping on SUCCESS, alerted on
#     absence) — healthchecks.io or similar. Worth adding; not this module.
#   * The host being off, or this module's own curl failing. Beszel covers the
#     first; nothing covers the second, which is inherent to push notification.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.notifyFailure;
in
{
  options.services.notifyFailure = {
    enable = lib.mkEnableOption "Telegram notifications for failed systemd units";

    tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to a file holding the Telegram bot credentials as an env file with
        `TELEGRAM_BOT_TOKEN=` and `TELEGRAM_CHAT_ID=` lines. Read as root via
        systemd EnvironmentFile, so an agenix secret at its 0400 default works.
      '';
    };

    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "service-backup-plex.service" ];
      description = ''
        Units to attach OnFailure to. Names must include the `.service` suffix.

        Caveat worth knowing: naming a unit that doesn't exist does NOT fail
        evaluation — it defines a new, empty unit with nothing but an OnFailure
        line. That unit is never started (nothing pulls it in), so the symptom
        of a typo is silently getting no alerts for the unit you meant. Check
        `systemctl show <unit> -p OnFailure` after a deploy if in doubt.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        systemd.services."notify-failure@" = {
          description = "Report %i's failure to Telegram";
          # No wantedBy: only ever pulled in by another unit's OnFailure.
          serviceConfig = {
            Type = "oneshot";
            EnvironmentFile = lib.mkIf (cfg.tokenFile != null) cfg.tokenFile;
            # Nothing here touches the filesystem beyond reading the journal.
            DynamicUser = true;
            SupplementaryGroups = [ "systemd-journal" ];
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
          };
          scriptArgs = "%i";
          script = ''
            set -uo pipefail
            unit="$1"

            if [ -z "''${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "''${TELEGRAM_CHAT_ID:-}" ]; then
              echo "notify-failure: no bot token/chat id configured; nothing sent for $unit" >&2
              exit 0
            fi

            result=$(${pkgs.systemd}/bin/systemctl show "$unit" --property=Result --value 2>/dev/null)
            code=$(${pkgs.systemd}/bin/systemctl show "$unit" --property=ExecMainStatus --value 2>/dev/null)
            # Last few journal lines are what makes the alert actionable rather
            # than just "something broke". Trimmed hard: Telegram caps a message
            # at 4096 chars and a truncated send is a failed send.
            log=$(${pkgs.systemd}/bin/journalctl -u "$unit" -n 15 --no-pager -o cat 2>/dev/null | ${pkgs.coreutils}/bin/tail -c 2500)

            text="🔴 ${config.networking.hostName}: $unit failed
            result=$result exit=$code

            $log"

            # --fail so a rejected send is a failed unit rather than silence;
            # --max-time so a hung api.telegram.org can't wedge this forever.
            ${pkgs.curl}/bin/curl -sS --fail --max-time 30 \
              -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
              --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
              --data-urlencode "text=$text" \
              --data-urlencode "disable_web_page_preview=true" \
              >/dev/null
          '';
        };
      }

      # Stamp OnFailure onto each listed unit. The target's name is baked into
      # the instance rather than using `%n`, which inside the template would
      # expand to the *notifier's* own name, not the unit that failed.
      #
      # No systemd-escape here: instance names only need escaping for `/`, and
      # every unit name in this fleet is plain [a-z0-9-]. Add escaping if that
      # ever stops being true.
      {
        systemd.services = lib.listToAttrs (
          map (
            u:
            let
              base = lib.removeSuffix ".service" u;
            in
            lib.nameValuePair base {
              onFailure = [ "notify-failure@${base}.service" ];
            }
          ) cfg.units
        );
      }
    ]
  );
}
