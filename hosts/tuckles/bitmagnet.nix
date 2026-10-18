{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.bitmagnet;
  # The database is capped at 128 GiB (pg_database_size; WAL, up to max_wal_size,
  # sits on top): past that, bitmagnet-cap pauses the crawler
  # by creating this flag, and bitmagnet runs without its dht_crawler worker.
  # Search, the web UI and the queue keep working; the index just stops growing.
  capBytes = 128 * 1024 * 1024 * 1024;
  pausedFlag = "/var/lib/bitmagnet-cap/crawl-paused";
  # The web UI leaves the airvpn netns through this Unix socket, which (like the
  # postgres socket) is on the shared filesystem rather than the network.
  webSocket = "/run/bitmagnet-web/http.sock";
in {
  # bitmagnet indexes torrents seen on the public DHT (names, file lists, sizes),
  # so a stalled qBittorrent download can be matched against other torrents that
  # carry a byte-identical file. The index is rebuildable by crawling, so it isn't
  # backed up.
  services.bitmagnet = {
    enable = true;
    # useLocalPostgresDB (default) creates the bitmagnet db/user on the host
    # postgresql. bitmagnet reaches it over the /run/postgresql Unix socket,
    # which network namespaces don't affect.
    settings = {
      # Loopback inside the netns only: the web UI and GraphQL API have no auth, and
      # the only way in is the Unix-socket bridge below (tsnsrv on the tailnet).
      http_server.local_address = "127.0.0.1:3333";
      # Log to stdout only, as JSON, so journald holds the structured logs.
      log = {
        json = true;
        file_rotator.enabled = false;
      };
      processor.concurrency = 3;
      # Matching relies on names and file sizes, not TMDB metadata.
      tmdb.enabled = false;
      dht_crawler = {
        # Upstream default is 10. tuckles' disk lives on the Synology's volume1,
        # whose saturation freezes this VM, so crawl gently.
        scaling_factor = 2;
        # Keep file lists for torrents with up to 1000 files (default 100) so
        # season packs stay matchable by file size.
        save_files_threshold = 1000;
        # Piece hashes can't be handed to qBittorrent as metadata, so storing
        # them would only cost disk.
        save_pieces = false;
      };
    };
  };

  services.postgresql = {
    # Pinned so a nixpkgs default bump never demands a pg_upgrade of the index.
    package = pkgs.postgresql_17;
    settings = {
      # Losing the last moments of crawl data on a crash is harmless (it's
      # recrawled), and skipping the per-commit fsync spares volume1.
      synchronous_commit = "off";
      shared_buffers = "1GB";
      effective_cache_size = "4GB";
      max_wal_size = "2GB";
    };
  };

  systemd.services.bitmagnet = {
    # Same AirVPN namespace as qBittorrent and slskd: the crawler's only egress
    # is the WireGuard tunnel, so it never crawls from the home IP.
    vpnConfinement = {
      enable = true;
      vpnNamespace = "airvpn";
    };
    serviceConfig = {
      # The module's RestrictNamespaces blocks joining the VPN netns.
      RestrictNamespaces = lib.mkForce false;
      ExecStart = lib.mkForce (pkgs.writeShellScript "bitmagnet-start" ''
        if [ -e ${pausedFlag} ]; then
          exec ${cfg.package}/bin/bitmagnet worker run --keys http_server --keys queue_server
        fi
        exec ${cfg.package}/bin/bitmagnet worker run --all
      '');
    };
  };

  # Inside the netns: expose bitmagnet's loopback-only HTTP port as a Unix socket.
  systemd.services.bitmagnet-web-socket = {
    description = "bitmagnet web UI (netns 127.0.0.1:3333) -> ${webSocket}";
    after = ["bitmagnet.service"];
    wantedBy = ["multi-user.target"];
    vpnConfinement = {
      enable = true;
      vpnNamespace = "airvpn";
    };
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat UNIX-LISTEN:${webSocket},fork,unlink-early,mode=0666 TCP4:127.0.0.1:3333";
      DynamicUser = true;
      RuntimeDirectory = "bitmagnet-web";
      RuntimeDirectoryMode = "0755";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # On the host: tsnsrv dials this localhost port, which feeds the socket above.
  systemd.services.bitmagnet-web-proxy = {
    description = "localhost:3335 -> bitmagnet web UI socket (for tsnsrv)";
    after = ["bitmagnet-web-socket.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat TCP4-LISTEN:3335,bind=127.0.0.1,fork,reuseaddr UNIX-CONNECT:${webSocket}";
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # bitmagnet-match <qB infohash> [min MiB]: look up every file of a stalled
  # qBittorrent torrent (above the size floor, default 10 MiB) by exact byte size
  # in the bitmagnet index, and list the other torrents that carry one, best match
  # first, as magnets to add at the same save path.
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "bitmagnet-match";
      runtimeInputs = [pkgs.curl pkgs.jq config.services.postgresql.package];
      text = ''
        if [ $# -lt 1 ] || [ $# -gt 2 ]; then
          echo "usage: bitmagnet-match <qbittorrent infohash> [min MiB, default 10]" >&2
          exit 2
        fi
        hash=''${1,,}
        min=$(( ''${2:-10} * 1024 * 1024 ))
        # qBittorrent's WebUI, reached at the airvpn netns address (see qui.nix).
        files=$(curl -fsS "http://192.168.15.1:6001/api/v2/torrents/files?hash=$hash")
        sizes=$(jq -r --argjson min "$min" \
          '[.[] | select(.size >= $min) | .size] | unique | "{\(join(","))}"' <<<"$files")
        if [ "$sizes" = "{}" ]; then
          echo "no files of $hash are at least $(( min / 1024 / 1024 )) MiB (or qBittorrent doesn't know it)" >&2
          exit 1
        fi
        total=$(jq -r --argjson min "$min" '[.[] | select(.size >= $min) | .size] | unique | length' <<<"$files")
        jq -r --argjson min "$min" '.[] | select(.size >= $min) | "looking for \(.size)  \(.name)"' <<<"$files"
        echo
        sudo -u postgres psql bitmagnet -qtAF $'\t' -v sizes="$sizes" -v self="$hash" <<'SQL' |
        with hits as (
          select info_hash, size from torrent_files where size = any(:'sizes'::bigint[])
          union
          select info_hash, size from torrents
           where files_status = 'single' and size = any(:'sizes'::bigint[])
        )
        select count(distinct h.size), encode(t.info_hash, 'hex'), t.name
          from hits h join torrents t using (info_hash)
         where t.info_hash <> decode(:'self', 'hex')
         group by t.info_hash, t.name
         order by 1 desc, t.name;
        SQL
          awk -F '\t' -v total="$total" '
            { found = 1; printf "%s/%s files  %s\n  magnet:?xt=urn:btih:%s\n", $1, total, $3, $2 }
            END { if (!found) print "no other torrent in the index carries these files yet" }'
      '';
    })
  ];

  # Hourly size check that pauses or resumes the crawler around capBytes.
  # BITMAGNET_CAP_BYTES overrides the cap (for testing).
  systemd.services.bitmagnet-cap = {
    description = "Pause bitmagnet's DHT crawler while its database is over the size cap";
    # postgresql.target includes postgresql-setup, which creates the bitmagnet db.
    after = ["postgresql.target"];
    serviceConfig.Type = "oneshot";
    path = [
      config.services.postgresql.package
      config.systemd.package
      pkgs.coreutils
      pkgs.util-linux
    ];
    script = ''
      cap=''${BITMAGNET_CAP_BYTES:-${toString capBytes}}
      if ! size=$(runuser -u postgres -- psql -d bitmagnet -tAc "select pg_database_size('bitmagnet')") \
        || ! [[ $size =~ ^[0-9]+$ ]]; then
        echo "bitmagnet db size query failed; leaving the crawler as it is" >&2
        exit 1 # fail the unit so a broken check shows in systemctl --failed
      fi
      if (( size >= cap )); then want=paused; else want=crawling; fi
      if [ -e ${pausedFlag} ]; then have=paused; else have=crawling; fi
      echo "bitmagnet db $(numfmt --to=iec "$size") / cap $(numfmt --to=iec "$cap") ($want)"
      if [ "$want" != "$have" ]; then
        if [ "$want" = paused ]; then touch ${pausedFlag}; else rm -f ${pausedFlag}; fi
        # try-restart leaves a deliberately stopped bitmagnet stopped; its next
        # start reads the flag anyway.
        systemctl try-restart bitmagnet.service
      fi
    '';
  };
  systemd.timers.bitmagnet-cap = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
  systemd.tmpfiles.rules = ["d /var/lib/bitmagnet-cap 0755 root root -"];
}
