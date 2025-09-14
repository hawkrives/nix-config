{pkgs, ...}: let
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
  services.plex = {
    enable = true;
    # package = pkgs.plex;
    group = "servarr";
    openFirewall = true;

    extraPlugins = [
      (builtins.path {
        name = "Hama.bundle";
        path = pkgs.fetchFromGitHub {
          owner = "ZeroQI";
          repo = "Hama.bundle";
          rev = "02f2025d6ffcceb973a2e3f72ec98b60ba9a60bd";
          sha256 = "xXgmPrRJkBtXW1REYnxb1w5U1a8R79UllUWrcfCnuk4=";
        };
      })
    ];

    extraScanners = [
      (pkgs.fetchFromGitHub {
        owner = "ZeroQI";
        repo = "Absolute-Series-Scanner";
        rev = "f41cd58eb72480c677ec6c9efec9de6adbad16ff";
        sha256 = "XE1yHsJQo9o46NlE5ToIhK4EXONFKjANtKY3dpTs9HE=";
      })
    ];
  };

  services.tautulli = {
    enable = true;
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
