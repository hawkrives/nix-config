# Watch nutmeg from outside nutmeg: an ssh probe from the NAS that alerts on
# Telegram when nutmeg stops answering. The Beszel hub and Uptime Kuma run
# here too; this is the direct "is nutmeg up" check. The same
# behaviour as modules/nixos/host-watch.nix + notify-failure.nix, as plain
# systemd-219 units.
#
# Telegram credentials: secrets/telegram-notify.age (TELEGRAM_BOT_TOKEN=… /
# TELEGRAM_CHAT_ID=…), decrypted by activate.
{
  config,
  pkgs,
  ...
}: let
  # nutmeg's tailnet IP, not a name: DNS failing would make this alert about
  # the wrong thing. sshd answers whenever the host is genuinely usable.
  host = "100.70.139.99";
  # nutmeg on the LAN, asked before alerting: if it answers there, nutmeg is
  # up and it is the tailnet path (often the NAS's own) that failed.
  lanHost = "2600:2b00:9b16:6d01::228"; # its stable LAN IPv6, as the Beszel agent uses
  port = 22;
  attempts = 5;
  gap = 30;

  probe = pkgs.writeShellScript "host-watch-nutmeg" ''
    set -uo pipefail
    for i in $(${pkgs.coreutils}/bin/seq ${toString attempts}); do
      if ${pkgs.netcat}/bin/nc -z -w 5 ${host} ${toString port} 2>/dev/null; then
        [ "$i" = 1 ] || echo "nutmeg: answered on attempt $i"
        exit 0
      fi
      echo "nutmeg: no answer on ${host}:${toString port} (attempt $i/${toString attempts})" >&2
      [ "$i" = ${toString attempts} ] || ${pkgs.coreutils}/bin/sleep ${toString gap}
    done
    if ${pkgs.netcat}/bin/nc -z -w 5 ${lanHost} ${toString port} 2>/dev/null; then
      echo "nutmeg answers on the LAN (${lanHost}) but not over the tailnet; not alerting" >&2
      exit 0
    fi
    echo "nutmeg is DOWN: no TCP answer on ${host}:${toString port} after ${toString attempts} attempts over ${toString (attempts * gap)}s, nor on ${lanHost}" >&2
    exit 1
  '';

  # notify-failure@<unit>: the unit's result and last log lines to Telegram,
  # retrying for ~8 minutes while Telegram is unreachable. DSM's own systemctl
  # and journalctl, which match its systemd.
  notify = pkgs.writeShellScript "notify-failure" ''
    set -uo pipefail
    unit="$1"
    if [ -z "''${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "''${TELEGRAM_CHAT_ID:-}" ]; then
      echo "notify-failure: no bot token/chat id configured; nothing sent for $unit" >&2
      exit 0
    fi
    result=$(/usr/bin/systemctl show "$unit" --property=Result 2>/dev/null | ${pkgs.coreutils}/bin/cut -d= -f2)
    code=$(/usr/bin/systemctl show "$unit" --property=ExecMainStatus 2>/dev/null | ${pkgs.coreutils}/bin/cut -d= -f2)
    log=$(/usr/bin/journalctl -u "$unit" -n 15 --no-pager -o cat 2>/dev/null | ${pkgs.coreutils}/bin/tail -c 2500)
    text="🔴 potato-bunny: $unit failed
    result=$result exit=$code
    $log"
    rc=0
    for _ in $(${pkgs.coreutils}/bin/seq 16); do
      rc=0
      ${pkgs.curl}/bin/curl -sS --fail --max-time 30 \
        -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
        --data-urlencode "text=$text" \
        --data-urlencode "disable_web_page_preview=true" \
        >/dev/null || rc=$?
      [ "$rc" -eq 0 ] && exit 0
      case "$rc" in
        6 | 7 | 28) ;;
        *)
          echo "notify-failure: curl exited $rc sending $unit's alert; not retryable" >&2
          exit 1
          ;;
      esac
      ${pkgs.coreutils}/bin/sleep 30
    done
    echo "notify-failure: api.telegram.org unreachable for ~8min (curl $rc); alert for $unit lost" >&2
    exit 1
  '';
in {
  age.secrets.telegram-notify.file = ../../secrets/telegram-notify.age;

  systemd.units."notify-failure@.service" = {
    wantedBy = [];
    text = ''
      [Unit]
      Description=Report %i's failure to Telegram

      [Service]
      Type=oneshot
      EnvironmentFile=-${config.age.secrets.telegram-notify.path}
      Environment=SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
      ExecStart=${notify} %i
    '';
  };

  systemd.units."host-watch-nutmeg.service" = {
    wantedBy = [];
    text = ''
      [Unit]
      Description=Check nutmeg (${host}:${toString port}) is answering
      OnFailure=notify-failure@%n.service

      [Service]
      Type=oneshot
      ExecStart=${probe}
    '';
  };
  systemd.units."host-watch-nutmeg.timer" = {
    wantedBy = ["timers.target"];
    text = ''
      [Unit]
      Description=Periodic reachability check for nutmeg

      [Timer]
      OnCalendar=*:0/5
      AccuracySec=30s
    '';
  };
}
