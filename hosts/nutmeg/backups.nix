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
      plex = {
        root = "${config.services.plex.dataDir}/Plex Media Server";
        sqlite = [
          "Plug-in Support/Databases/com.plexapp.plugins.library.db"
          "Plug-in Support/Databases/com.plexapp.plugins.library.blobs.db"
        ];
        path = "Preferences.xml"; # never rsync the Cache/Metadata/Media trees
      };
      # HA writes its automatic backups to this local dir and prunes its own
      # retention (see home-assistant.nix); this is their only offsite copy.
      # Nothing here holds an NFS mount, so unlike the rest of the fleet the
      # tars are already local — this job just mirrors them to the NAS.
      home-assistant = {
        root = config.users.users.homeassistant.home;
        path = "backups";
      };

      soularr = {
        root = "/var/lib/soularr";
        # config.ini is rendered from nix; the failed-import denylist is the only
        # real runtime state. Whole dir minus the stale lock.
        excludes = [ "*.lock" ];
      };

      # Beszel monitoring hub (PocketBase). The metric history and the admin
      # account both live in data.db; the data dir also has an auxiliary.db,
      # but it only holds PocketBase's internal request log, so it's skipped.
      # The rest of /var/lib/beszel-hub outside beszel_data is regenerable, so
      # only beszel_data is rsynced. That rsync also carries beszel_data's
      # id_ed25519 — the hub's PRIVATE key — which is deliberate, not
      # incidental cruft: a restored hub that generated a fresh keypair would
      # break every agent's inline KEY (modules/nixos/beszel-agent.nix, and
      # the Synology compose in docs/beszel-synology.md). A real restore
      # needs both data.db and id_ed25519 back in place.
      beszel = {
        root = "/var/lib/beszel-hub";
        sqlite = [ "beszel_data/data.db" ];
        path = "beszel_data";
      };
    };
  };
}
