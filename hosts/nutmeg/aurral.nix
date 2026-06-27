{ ... }:
{
  # Dedicated identity. gid 100 ("users") gives NAS group-write on the media
  # tree (same model as lidarr/beets/plex); uid/gid 10012 follows the HA
  # containers (10010/10011).
  users.groups.aurral.gid = 10012;
  users.users.aurral = {
    uid = 10012;
    group = "aurral";
    extraGroups = [ "users" ];
    home = "/var/lib/aurral";
    isNormalUser = true;
  };

  # Local appdata dir for the SQLite/config bind mount.
  systemd.tmpfiles.rules = [
    "d /var/lib/aurral 0750 aurral aurral - -"
  ];

  # Aurral — a Lidarr music-discovery/request front-end ("Seerr for music").
  # Docker-first, no Nix package, so it runs as a podman container like the
  # matter server. Lidarr is connected at runtime in Aurral's web UI
  # (http://127.0.0.1:8686 + the lidarr API key); nothing declarative here.
  virtualisation.oci-containers.containers.aurral = {
    image = "ghcr.io/lklynet/aurral:latest";
    autoStart = true;
    # Run as the aurral uid but gid 100 ("users") so files land on the NAS with
    # the shared group, matching the media tree's ownership.
    user = "10012:100";
    volumes = [
      "/var/lib/aurral:/app/backend/data" # SQLite appdata/config (local)
      "/mnt/music/aurral:/app/downloads" # staging downloads (NAS)
    ];
    environment.TZ = "America/New_York";
    labels."io.containers.autoupdate" = "registry";
    extraOptions = [
      "--pull=newer"
      "--network=host" # reach Lidarr at 127.0.0.1:8686; listen on :3001
      "--umask=0007" # new files carry group-write for the NAS model
    ];
  };

  # /mnt/music is an x-systemd.automount (idle-timeout 5m). Order the container
  # after the mount so the /mnt/music/aurral bind source is present at start; a
  # live bind keeps the mount referenced, so it won't idle-unmount underneath.
  systemd.services.podman-aurral.unitConfig.RequiresMountsFor = "/mnt/music";

  # Expose on the tailnet, like the other apps.
  services.tsnsrv.services.aurral.urlParts.port = 3001;
}
