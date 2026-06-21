{ pkgs, synologyMount, ... }:
{
  # Mount the app-servarr share read-write for backups.
  fileSystems."/mnt/servarr" = synologyMount "/volume1/app-servarr" { };

  systemd.services.download-client-config-backup = {
    description = "Back up SAB/qB config dirs to the NAS";
    path = [ pkgs.rsync ];
    serviceConfig.Type = "oneshot";
    script = ''
      dest=/mnt/servarr/backups/tuckles
      mkdir -p "$dest"
      rsync -a --delete /var/lib/sabnzbd/ "$dest/sabnzbd/"
      rsync -a --delete /var/lib/qBittorrent/ "$dest/qbittorrent/"
    '';
  };

  systemd.timers.download-client-config-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
