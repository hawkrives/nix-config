{
  lib,
  pkgs,
  config,
  ...
}:
let
  synology = "192.168.1.194";
  nfsMount =
    sharePath:
    {
      readOnly ? false,
    }:
    {
      fsType = "nfs";
      device = sharePath;
      options = [
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

  hama = builtins.path {
    name = "Hama.bundle";
    path = pkgs.fetchFromGitHub {
      # https://github.com/ZeroQI/Hama.bundle
      owner = "ZeroQI";
      repo = "Hama.bundle";
      rev = "adee212b7b419790f89ed127e59e13a8e1ff63f5";
      sha256 = "PgZAqK3Ooz8JgMqCW7hZOBzuaVjCywA6ytx33J/WqC4=";
    };
  };

  youtubeAgent = builtins.path {
    name = "YouTube-Agent.bundle";
    path = pkgs.fetchFromGitHub {
      # https://github.com/ZeroQI/YouTube-Agent.bundle
      owner = "ZeroQI";
      repo = "YouTube-Agent.bundle";
      rev = "e63f7a81b3493cf522a3d58276bc2ed117ed206c";
      sha256 = "W1lY9uDqxkkKmxBDewQc/BOsZSK2CbKHRBTzTscR68Y=";
    };
  };

  absoluteSeriesScanner = pkgs.fetchFromGitHub {
    # https://github.com/ZeroQI/Absolute-Series-Scanner
    owner = "ZeroQI";
    repo = "Absolute-Series-Scanner";
    rev = "a3af601f8e127c027edc387c1e4d64927c9f25fc";
    sha256 = "BgwLzvzV4+jWePgZPOkbY2jnO4qwL8cgaTBl4R4uMRA=";
  };
in
{
  services.plex = {
    enable = true;
    openFirewall = true;

    extraPlugins = [
      hama
      youtubeAgent
    ];

    extraScanners = [
      absoluteSeriesScanner
    ];
  };

  services.tautulli = {
    # enable = true;
    enable = false;
    openFirewall = true;

    dataDir = "/var/lib/tautulli";
  };

  services.tsnsrv.services.tautulli-nm.urlParts.port = config.services.tautulli.port;
  services.tsnsrv.services.plex-nm.urlParts.port = 32400;

  fileSystems."/var/lib/plex/media-shows" = synologyMount "/volume1/media-shows" { };
  fileSystems."/var/lib/plex/media-channels" = synologyMount "/volume1/media-channels" { };
  fileSystems."/var/lib/plex/media-music" = synologyMount "/volume1/media-music" { };
  fileSystems."/var/lib/plex/media-movies" = synologyMount "/volume1/media-movies" { };

  fileSystems."/var/lib/plex/backup" = synologyMount "/volume1/app-plex" { };

  # need uid/gid to match the NAS
  # users.groups.servarr.gid = 1050;
  # users.users.servarr = {
  #   uid = 1036;
  #   isNormalUser = true;
  #   group = "servarr";
  #   home = "/var/lib/servarr";
  # };
}
