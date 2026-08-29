{ config, lib, ... }:
let
  arrExcludes = [ "MediaCover" "Backups" "logs" ];
in
{
  # Telegram push for anything here that fails. The service-backup jobs are the
  # motivating case: they run at 00:00-01:00, nobody watches the journal, and a
  # backup that quietly stopped working is only discovered when it's needed.
  age.secrets.telegram-notify.file = ../../secrets/telegram-notify.age;
  services.notifyFailure = {
    enable = true;
    tokenFile = config.age.secrets.telegram-notify.path;
    units = [
      # Everything timer-driven and unattended on this host.
      "arr-backup-pin.service"
      "beets-sync.service"
      "soularr.service"
      "lidarr-beets-pin.service"
      "recyclarr.service"
      "adf-autoscan.service"
      "avahi-name-check.service"
    ]
    # …plus one per service-backup job, derived from the jobs themselves so a
    # new job can't be added without also being watched.
    ++ map (n: "service-backup-${n}.service") (
      lib.attrNames config.services.serviceBackup.jobs
    );
  };

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

      # beets' library.db. Worth more than its 173MB suggests: the first
      # mbsync pass over the whole library runs at MusicBrainz's ~1 req/s rate
      # limit and takes hours (see beets.nix), so rebuilding this from scratch
      # is days, not minutes. Snapshotted rather than copied because beets
      # writes it live.
      #
      # state.pickle is kept deliberately — it is what makes `incremental =
      # true` skip already-imported directories. Dropped: the two
      # library.db-before-*.bak migration leftovers from 2026-08-05 (298MB
      # combined, superseded), import.log, and the config.yaml symlink, which
      # points into the nix store and would restore as a dangling link.
      beets = {
        root = "/var/lib/beets";
        sqlite = [ "library.db" ];
        excludes = [
          "*.bak"
          "import.log"
          "config.yaml"
        ];
      };

      # slime-chat's SQLite holds the minted Twitch OAuth tokens, so it is
      # real state rather than a cache. Handled here rather than as a direct
      # restic path so it gets a proper `sqlite3 .backup` snapshot — the
      # database is live and being written, and copying a hot SQLite file can
      # capture a torn page. restic picks the result up from this tree.
      #
      # playlists/ is 773MB of downloaded audio and is excluded; the database
      # is 64KB.
      slime-chat = {
        root = "/var/lib/slime-chat";
        sqlite = [ "villager-chat.db" ];
        excludes = [ "playlists" ];
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
