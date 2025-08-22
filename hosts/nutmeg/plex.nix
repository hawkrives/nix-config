{pkgs, ...}: let
  nfsOptions = [
    "nfsvers=4.1"
    "noatime"
    "noauto"
    "x-systemd.automount"
    "x-systemd.idle-timeout=60"
    "x-systemd.device-timeout=5s"
    "x-systemd.mount-timeout=5s"
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

  # TODO: move to home-manager?
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

  # TODO: replace with getting avahi working on the network
  # so .local addresses work
  # networking.hosts = {
  #   "192.168.1.194" = ["plex-nas"];
  # };

  fileSystems."/var/lib/plex/media-shows" = {
    fsType = "nfs";
    device = "potato-bunny.local:/volume1/media-shows";
    options = readOnlyNfs;
  };

  fileSystems."/var/lib/plex/media-channels" = {
    fsType = "nfs";
    device = "potato-bunny.local:/volume1/media-channels";
    options = readOnlyNfs;
  };

  fileSystems."/var/lib/plex/media-photos" = {
    fsType = "nfs";
    device = "potato-bunny.local:/volume1/media-photos";
    options = readOnlyNfs;
  };

  fileSystems."/var/lib/plex/media-music" = {
    fsType = "nfs";
    device = "potato-bunny.local:/volume1/media-music";
    options = readOnlyNfs;
  };

  fileSystems."/var/lib/plex/media-movies" = {
    fsType = "nfs";
    device = "potato-bunny.local:/volume1/media-movies";
    options = readOnlyNfs;
  };

  fileSystems."/var/lib/plex/backup" = {
    fsType = "nfs";
    device = "potato-bunny.local:/volume1/app-plex";
    options = nfsOptions;
  };
}
