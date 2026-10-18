{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.bitmagnet;
  # The index is capped at 128 GiB: past that, bitmagnet-cap pauses the crawler
  # by creating this flag, and bitmagnet runs without its dht_crawler worker.
  # Search, the web UI and the queue keep working; the index just stops growing.
  capBytes = 128 * 1024 * 1024 * 1024;
  pausedFlag = "/var/lib/bitmagnet-cap/crawl-paused";
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
      http_server.local_address = ":3333";
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

  # tsnsrv can't dial into the airvpn netns (see slskd-web-proxy in slskd.nix),
  # so the bitmagnet tsnsrv node goes through this plain localhost forwarder.
  systemd.services.bitmagnet-web-proxy = {
    description = "localhost:3335 -> bitmagnet web UI in the airvpn netns (for tsnsrv)";
    after = ["bitmagnet.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat TCP4-LISTEN:3335,bind=127.0.0.1,fork,reuseaddr TCP4:192.168.15.1:3333";
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Hourly size check that pauses or resumes the crawler around capBytes.
  # BITMAGNET_CAP_BYTES overrides the cap (for testing).
  systemd.services.bitmagnet-cap = {
    description = "Pause bitmagnet's DHT crawler while its database is over the size cap";
    after = ["postgresql.service"];
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
        exit 0
      fi
      if (( size >= cap )); then want=paused; else want=crawling; fi
      if [ -e ${pausedFlag} ]; then have=paused; else have=crawling; fi
      echo "bitmagnet db $(numfmt --to=iec "$size") / cap $(numfmt --to=iec "$cap") ($want)"
      if [ "$want" != "$have" ]; then
        if [ "$want" = paused ]; then touch ${pausedFlag}; else rm -f ${pausedFlag}; fi
        systemctl restart bitmagnet.service
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
