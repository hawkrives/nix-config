{
  config,
  pkgs,
  ...
}: let
  # One-off Telegram report of what the plex_egress table (./plex.nix) saw, as
  # input for deciding whether to enforce a port allowlist on Plex's internet
  # traffic. Delete this file once that's decided.
  sessionId = "a1e23ff4-36f6-532a-a400-dc3e0fd2407c";

  plex-egress-review = pkgs.writeShellApplication {
    name = "plex-egress-review";
    runtimeInputs = [pkgs.nftables pkgs.jq pkgs.curl pkgs.coreutils pkgs.gnugrep pkgs.gnused config.systemd.package];
    text = ''
      # The table, and so its counters, is recreated on every nftables
      # (re)load; count from the last one.
      since=$(journalctl -u nftables -o short-iso --no-pager \
        | grep -E 'Started|Reloaded' | tail -1 | cut -d' ' -f1)
      [ -n "$since" ] || since=$(systemctl show nftables -p ActiveEnterTimestamp --value)

      ports=$(nft -j list set inet plex_egress plex_ports | jq -r '
        [.nftables[] | .set? // empty | .elem // [] | .[]]
        | sort_by(-.elem.counter.packets) | .[]
        | "\(.elem.counter.packets)  \(.elem.val.concat[0])/\(.elem.val.concat[1])"')

      # "count  DST proto/port", most frequent first, from the kernel log lines
      # the plex_egress rules write.
      top() {
        journalctl -k --since "$since" -o cat --no-pager \
          | grep -F "$1" \
          | sed -nE 's/.*DST=([^ ]+) .*PROTO=([A-Z0-9]+) .*DPT=([0-9]+).*/\1 \2\/\3/p' \
          | sort | uniq -c | sort -rn | head -15 \
          | sed -E 's/^ *([0-9]+) /\1  /'
      }
      rejects=$(top 'plex-egress-reject: ')
      unusual=$(top 'plex-egress: ')

      msg="🗓 ${config.networking.hostName}: Plex egress review (counting since $since)

      New internet connections Plex made, by port:
      ''${ports:-(none)}

      Rejected local/LAN connections, top 15:
      ''${rejects:-(none)}

      Internet destinations off ports 53/80/443, top 15:
      ''${unusual:-(none)}

      (Log lines are rate-limited to 30/min, so those two lists are lower bounds.)

      Time to decide on a port allowlist for Plex with Claude:
      cd ~/nix-config && claude --resume ${sessionId}
      Then delete hosts/nutmeg/plex-egress-review.nix."

      curl -fsS --max-time 30 --retry 5 --retry-connrefused \
        -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
        --data-urlencode "text=''${msg:0:4000}" \
        -d disable_web_page_preview=true >/dev/null
    '';
  };
in {
  systemd.services.plex-egress-review = {
    description = "Send the Plex egress review to Telegram";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${plex-egress-review}/bin/plex-egress-review";
      EnvironmentFile = config.age.secrets.telegram-notify.path;
    };
  };
  systemd.timers.plex-egress-review = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "2026-10-26 09:52:00";
      Persistent = true;
    };
  };

  services.notifyFailure.units = ["plex-egress-review.service"];
}
