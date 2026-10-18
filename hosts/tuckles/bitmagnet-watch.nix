{
  config,
  pkgs,
  ...
}: let
  # qBittorrent's WebUI API, reached at the airvpn netns address (see qui.nix).
  qbApi = "http://192.168.15.1:6001/api/v2/torrents";

  # bitmagnet-match [--tsv] <qB infohash> [min MiB]: look up every file of a
  # qBittorrent torrent (above the size floor, default 10 MiB) by exact byte size
  # in the bitmagnet index, and list the other torrents that carry one, best match
  # first, as magnets to add at the same save path. --tsv prints
  # matched<TAB>total<TAB>infohash<TAB>name rows for bitmagnet-watch instead.
  bitmagnet-match = pkgs.writeShellApplication {
    name = "bitmagnet-match";
    runtimeInputs = [pkgs.curl pkgs.jq pkgs.util-linux config.services.postgresql.package];
    text = ''
      tsv=false
      if [ "''${1:-}" = --tsv ]; then tsv=true; shift; fi
      if [ $# -lt 1 ] || [ $# -gt 2 ]; then
        echo "usage: bitmagnet-match [--tsv] <qbittorrent infohash> [min MiB, default 10]" >&2
        exit 2
      fi
      hash=''${1,,}
      min=$(( ''${2:-10} * 1024 * 1024 ))
      files=$(curl -fsS "${qbApi}/files?hash=$hash")
      wanted="[.[] | select(.size >= \$min) | .size] | unique"
      sizes=$(jq -r --argjson min "$min" "$wanted | \"{\(join(\",\"))}\"" <<<"$files")
      total=$(jq -r --argjson min "$min" "$wanted | length" <<<"$files")
      if [ "$total" = 0 ]; then
        echo "no files of $hash are at least $(( min / 1024 / 1024 )) MiB (or qBittorrent has no file list for it)" >&2
        exit 1
      fi
      psql_as_postgres() {
        if [ "$(id -u)" = 0 ]; then runuser -u postgres -- psql "$@"; else sudo -u postgres psql "$@"; fi
      }
      rows=$(psql_as_postgres bitmagnet -qtAF $'\t' -v sizes="$sizes" -v self="$hash" -v total="$total" <<'SQL'
      with hits as (
        select info_hash, size from torrent_files where size = any(:'sizes'::bigint[])
        union
        select info_hash, size from torrents
         where files_status = 'single' and size = any(:'sizes'::bigint[])
      )
      select count(distinct h.size), :'total', encode(t.info_hash, 'hex'), t.name
        from hits h join torrents t using (info_hash)
       where t.info_hash <> decode(:'self', 'hex')
       group by t.info_hash, t.name
       order by 1 desc, t.name;
      SQL
      )
      if $tsv; then
        [ -z "$rows" ] || printf '%s\n' "$rows"
        exit 0
      fi
      jq -r --argjson min "$min" '.[] | select(.size >= $min) | "looking for \(.size)  \(.name)"' <<<"$files"
      echo
      if [ -z "$rows" ]; then
        echo "no other torrent in the index carries these files yet"
        exit 0
      fi
      while IFS=$'\t' read -r matched all other name; do
        printf '%s/%s files  %s\n  magnet:?xt=urn:btih:%s\n' "$matched" "$all" "$name" "$other"
      done <<<"$rows"
    '';
  };

  # Report new bitmagnet matches for stalled qBittorrent downloads to Telegram.
  # It only reports: a size match can be a coincidence, so adding the magnet is
  # left to a human. Each (torrent, match) pair is reported once.
  bitmagnet-watch = pkgs.writeShellApplication {
    name = "bitmagnet-watch";
    runtimeInputs = [bitmagnet-match pkgs.curl pkgs.jq pkgs.util-linux config.services.postgresql.package];
    text = ''
      reported=/var/lib/bitmagnet-watch/reported
      touch "$reported"

      send() {
        curl -fsS --max-time 30 --retry 5 --retry-connrefused \
          -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
          --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
          --data-urlencode "text=''${1:0:4000}" \
          -d disable_web_page_preview=true >/dev/null
      }

      torrents=$(curl -fsS "${qbApi}/info?filter=all")

      # Stalled downloads: match their large files (100 MiB floor keeps size
      # coincidences rare) against other torrents in the index.
      while IFS=$'\t' read -r hash name; do
        rows=$(bitmagnet-match --tsv "$hash" 100) || continue
        message=""
        keys=()
        while IFS=$'\t' read -r matched total other other_name; do
          [ -n "$other" ] || continue
          grep -qxF "$hash $other" "$reported" && continue
          message+="$matched/$total files  $other_name"$'\n'"magnet:?xt=urn:btih:$other"$'\n\n'
          keys+=("$hash $other")
        done <<<"$rows"
        if [ -n "$message" ]; then
          send "bitmagnet: same files as stalled \"$name\""$'\n\n'"$message"
          printf '%s\n' "''${keys[@]}" >>"$reported"
        fi
      done < <(jq -r '.[] | select(.state == "stalledDL") | [.hash, .name] | @tsv' <<<"$torrents")

      # Metadata-stuck torrents have no file list to match, but if bitmagnet has
      # indexed the hash, some peer served its metadata, and the name says what it is.
      while read -r hash; do
        grep -qxF "$hash seen" "$reported" && continue
        seen=$(runuser -u postgres -- psql bitmagnet -qtAF $'\t' -v hash="$hash" <<'SQL'
      select name, pg_size_pretty(size) from torrents where info_hash = decode(:'hash', 'hex');
      SQL
        )
        [ -n "$seen" ] || continue
        IFS=$'\t' read -r seen_name seen_size <<<"$seen"
        send "bitmagnet has seen metadata-stuck $hash: \"$seen_name\" ($seen_size), so a peer served its metadata recently"
        echo "$hash seen" >>"$reported"
      done < <(jq -r '.[] | select(.state == "metaDL" or .state == "forcedMetaDL") | .hash' <<<"$torrents")
    '';
  };
in {
  environment.systemPackages = [bitmagnet-match];

  systemd.services.bitmagnet-watch = {
    description = "Report bitmagnet matches for stalled qBittorrent downloads to Telegram";
    after = ["postgresql.target" "bitmagnet.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${bitmagnet-watch}/bin/bitmagnet-watch";
      EnvironmentFile = config.age.secrets.telegram-notify.path;
      StateDirectory = "bitmagnet-watch";
    };
  };
  systemd.timers.bitmagnet-watch = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "00/6:00";
      Persistent = true;
    };
  };

  services.notifyFailure.units = ["bitmagnet-cap.service" "bitmagnet-watch.service"];
}
