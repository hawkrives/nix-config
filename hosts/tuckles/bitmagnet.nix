{
  lib,
  pkgs,
  ...
}: {
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
    # The module's RestrictNamespaces blocks joining the VPN netns.
    serviceConfig.RestrictNamespaces = lib.mkForce false;
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
}
