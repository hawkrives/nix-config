{
  lib,
  config,
  ...
}: let
  synology = "192.168.1.194";
  nfsMount = sharePath: {readOnly ? false}: {
    fsType = "nfs";
    device = sharePath;
    options =
      [
        "nfsvers=4.1"
        "noatime" # we do not care about tracking the access time
        "_netdev" # ensure it's treated as a network fs, rather than local
        "x-systemd.automount" # enable mounting on first access
        "x-systemd.idle-timeout=5m" # unmount after this long
        "x-systemd.device-timeout=15s" # wait for a device to show up before giving up
        "x-systemd.mount-timeout=15s" # grace period for the actual mount call
      ]
      ++ lib.lists.optionals readOnly [
        "ro"
      ];
  };
  synologyMount = sharePath: options: nfsMount "${synology}:${sharePath}" options;

  servarrApp = {
    enable = true;
    openFirewall = true;

    settings.log.dbEnabled = false; # avoid writing logs to the database
    settings.auth.method = "External"; # disable auth requirement
    settings.update.mechanism = "external"; # disable builtin update process
  };
in {
  fileSystems."/mnt/photos" = synologyMount "/volume1/media-photos" {readOnly = true;};
  fileSystems."/mnt/shows" = synologyMount "/volume1/media-shows" {readOnly = true;};
  fileSystems."/mnt/channels" = synologyMount "/volume1/media-channels" {readOnly = true;};
  fileSystems."/mnt/music" = synologyMount "/volume1/media-music" {readOnly = true;};
  fileSystems."/mnt/movies" = synologyMount "/volume1/media-movies" {readOnly = true;};

  # ── Radarr (:7878) ────────────────────────────────────────────────
  services.radarr = servarrApp;
  services.tsnsrv.services.radarr-nm.urlParts.port = config.services.radarr.settings.server.port;

  # ── Sonarr (:8989) ────────────────────────────────────────────────
  services.sonarr = servarrApp;
  services.tsnsrv.services.sonarr-nm.urlParts.port = config.services.sonarr.settings.server.port;

  # ── Prowlarr (:9696) ——————————————————————————————————————————————
  services.prowlarr = servarrApp;
  services.tsnsrv.services.prowlarr-nm.urlParts.port = config.services.prowlarr.settings.server.port;

  # ── Lidarr (:8686) ────────────────────────────────────────────────
  services.lidarr = servarrApp;
  services.tsnsrv.services.lidarr-nm.urlParts.port = config.services.lidarr.settings.server.port;

  # ── Recyclarr ─────────────────────────────────────────────────────
  services.recyclarr.enable = true;

  # ── FlareSolverr (:8191) —─────────────────────────────────────────
  services.flaresolverr = {
    enable = true;
    # openFirewall = true;
  };

  # ── Bazarr (:6767) ────────────────────────────────────────────────
  services.bazarr = {
    enable = true;
    openFirewall = true;
  };
  services.tsnsrv.services.bazarr-nm.urlParts.port = config.services.bazarr.listenPort;

  # ── Overseerr (:5055) —────────────────────────────────────────────
  services.overseerr = {
    enable = true;
    openFirewall = true;
  };
  services.tsnsrv.services.seerr-nm.urlParts.port = config.services.overseerr.port;
}
