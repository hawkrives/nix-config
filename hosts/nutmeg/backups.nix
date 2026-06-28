{ config, ... }:
let
  arrExcludes = [ "MediaCover" "Backups" "logs" ];
in
{
  services.serviceBackup = {
    enable = true;
    # dest defaults to /mnt/servarr/backups/nutmeg
    jobs = {
      sonarr = {
        root = config.services.sonarr.dataDir; # /var/lib/sonarr/.config/NzbDrone
        sqlite = [ "sonarr.db" ];
        excludes = arrExcludes;
      };
      radarr = {
        root = config.services.radarr.dataDir; # /var/lib/radarr/.config/Radarr
        sqlite = [ "radarr.db" ];
        excludes = arrExcludes;
      };
      lidarr = {
        root = config.services.lidarr.dataDir; # /var/lib/lidarr/.config/Lidarr
        sqlite = [ "lidarr.db" ];
        excludes = arrExcludes;
      };
      prowlarr = {
        root = config.services.prowlarr.dataDir; # /var/lib/prowlarr (DynamicUser-symlinked)
        sqlite = [ "prowlarr.db" ];
        excludes = arrExcludes;
      };
      bazarr = {
        root = config.services.bazarr.dataDir; # /var/lib/bazarr
        sqlite = [ "db/bazarr.db" ];
        path = "config"; # config/config.yaml etc.
      };
      jellyseerr = {
        root = config.services.seerr.configDir; # /var/lib/jellyseerr/config (DynamicUser)
        sqlite = [ "db/db.sqlite3" ];
        path = "settings.json";
      };
      tautulli = {
        root = config.services.tautulli.dataDir; # /var/lib/tautulli
        sqlite = [ "tautulli.db" ];
        path = "config.ini";
      };
      jellyfin = {
        root = config.services.jellyfin.dataDir; # /var/lib/jellyfin
        sqlite = [
          "data/library.db"
          "data/jellyfin.db"
        ];
        path = "config"; # system.xml, network.xml, encoding.xml
        excludes = [ "metadata" "transcodes" "data/subtitles" ]; # regenerable
      };
      plex = {
        root = "${config.services.plex.dataDir}/Plex Media Server";
        sqlite = [
          "Plug-in Support/Databases/com.plexapp.plugins.library.db"
          "Plug-in Support/Databases/com.plexapp.plugins.library.blobs.db"
        ];
        path = "Preferences.xml"; # never rsync the Cache/Metadata/Media trees
      };
      soularr = {
        root = "/var/lib/soularr";
        # config.ini is rendered from nix; the failed-import denylist is the only
        # real runtime state. Whole dir minus the stale lock.
        excludes = [ "*.lock" ];
      };
    };
  };
}
