{
  pkgs,
  pkgsUnstable,
  flake,
  ...
}: let
  nfsOptions = [
    "nfsvers=4.1"
    "noatime" # we do not care about tracking the access time
    "_netdev" # ensure it's treated as a network fs, rather than local
    "x-systemd.automount" # enable mounting on first access
    "x-systemd.idle-timeout=5m" # unmount after this long
    "x-systemd.device-timeout=15s" # wait for a device to show up before giving up
    "x-systemd.mount-timeout=15s" # grace period for the actual mount call
  ];
  readOnlyNfs = nfsOptions ++ ["ro"];
in {
  imports = [
    flake.modules.common.nixpkgs-unstable # provides the pkgsUnstable argument
  ];

  services.plex = {
    enable = true;
    package = pkgsUnstable.plex;
    group = "servarr";
    openFirewall = true;

    extraPlugins = [
      (builtins.path {
        name = "Hama.bundle";
        path = pkgs.fetchFromGitHub {
          # https://github.com/ZeroQI/Hama.bundle
          owner = "ZeroQI";
          repo = "Hama.bundle";
          rev = "adee212b7b419790f89ed127e59e13a8e1ff63f5";
          sha256 = "PgZAqK3Ooz8JgMqCW7hZOBzuaVjCywA6ytx33J/WqC4=";
        };
      })

      (builtins.path {
        name = "YouTube-Agent.bundle";
        path = pkgs.fetchFromGitHub {
          # https://github.com/ZeroQI/YouTube-Agent.bundle
          owner = "ZeroQI";
          repo = "YouTube-Agent.bundle";
          rev = "e63f7a81b3493cf522a3d58276bc2ed117ed206c";
          sha256 = "W1lY9uDqxkkKmxBDewQc/BOsZSK2CbKHRBTzTscR68Y=";
        };
      })
    ];

    extraScanners = [
      (pkgs.fetchFromGitHub {
        # https://github.com/ZeroQI/Absolute-Series-Scanner
        owner = "ZeroQI";
        repo = "Absolute-Series-Scanner";
        rev = "a3af601f8e127c027edc387c1e4d64927c9f25fc";
        sha256 = "BgwLzvzV4+jWePgZPOkbY2jnO4qwL8cgaTBl4R4uMRA=";
      })
    ];
  };

  # need uid/gid to match the NAS
  users.groups.servarr.gid = 1050;
  users.users.servarr = {
    uid = 1036;
    isNormalUser = true;
    group = "servarr";
    home = "/var/lib/servarr";
  };

  # for mount=type=cifs
  environment.systemPackages = [pkgs.cifs-utils];

  fileSystems."/var/lib/plex/media-shows" = {
    fsType = "nfs";
    device = "192.168.1.194:/volume1/media-shows";
    options = readOnlyNfs;
  };

  fileSystems."/var/lib/plex/media-channels" = {
    fsType = "nfs";
    device = "192.168.1.194:/volume1/media-channels";
    options = readOnlyNfs;
  };

  fileSystems."/var/lib/plex/media-photos" = {
    fsType = "nfs";
    device = "192.168.1.194:/volume1/media-photos";
    options = readOnlyNfs;
  };

  fileSystems."/var/lib/plex/media-music" = {
    fsType = "nfs";
    device = "192.168.1.194:/volume1/media-music";
    options = readOnlyNfs;
  };

  fileSystems."/var/lib/plex/media-movies" = {
    fsType = "nfs";
    device = "192.168.1.194:/volume1/media-movies";
    options = readOnlyNfs;
  };

  fileSystems."/var/lib/plex/backup" = {
    fsType = "nfs";
    device = "192.168.1.194:/volume1/app-plex";
    options = nfsOptions;
  };
}
