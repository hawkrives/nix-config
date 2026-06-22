{ synologyMount, ... }:
{
  # Mount the app-servarr share read-write; it's the backup destination.
  fileSystems."/mnt/servarr" = synologyMount "/volume1/app-servarr" { };

  services.serviceBackup = {
    enable = true;
    # dest defaults to /mnt/servarr/backups/tuckles
    jobs = {
      sabnzbd = {
        root = "/var/lib/sabnzbd";
        sqlite = [ "admin/history1.db" ];
        # keep sabnzbd.ini + admin/*.sab + nzbs/; drop the bulky/transient dirs.
        excludes = [ "Downloads" "logs" "backups" "incomplete" "complete" ];
      };
      qbittorrent = {
        root = "/var/lib/qBittorrent";
        # qBittorrent/{config/*.conf,data/BT_backup}; skip the download scratch dirs.
        excludes = [ "incomplete" "complete" ];
      };
      slskd = {
        # Config is rendered into /run; the data/*.db files are the real state.
        root = "/var/lib/slskd/data";
        sqlite = [ "transfers.db" "messaging.db" "events.db" "search.db" ];
        excludes = [ "shares.local.bak.db" ]; # regenerable share index (also *.db-excluded)
      };
      qui = {
        root = "/var/lib/qui";
        sqlite = [ "qui.db" ]; # instances + cross-seed config set via the UI
        path = "config.toml";
      };
    };
  };
}
