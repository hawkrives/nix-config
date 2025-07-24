{ pkgs, pkgs-unstable, ... }:

let
  nfsOptions = [
    "nfsvers=4.1"
    "noatime"
    "noauto"
    "x-systemd.automount"
    "x-systemd.idle-timeout=60"
    "x-systemd.device-timeout=5s"
    "x-systemd.mount-timeout=5s"
  ];

in
{
  services.plex = {
    enable = true;
    package = pkgs-unstable.plex;
    group = "servarr";
    openFirewall = true;
  };

  services.tautulli = {
    enable = true;
  };

  users.groups.servarr = {
    gid = 1050;
  };
  users.users.servarr = {
    uid = 1036;
    isNormalUser = true;
    group = "servarr";
    home = "/var/lib/servarr";
  };

  # for mount=type=cifs
  environment.systemPackages = [ pkgs.cifs-utils ];

  services.plex.extraPlugins = [
    (builtins.path {
      name = "Hama.bundle";
      path = pkgs.fetchFromGitHub {
        owner = "ZeroQI";
        repo = "Hama.bundle";
        rev = "02f2025d6ffcceb973a2e3f72ec98b60ba9a60bd";
        sha256 = "";
      };
    })
  ];

  services.plex.extraScanners = [
    (pkgs.fetchFromGitHub {
      owner = "ZeroQI";
      repo = "Absolute-Series-Scanner";
      rev = "f41cd58eb72480c677ec6c9efec9de6adbad16ff";
      sha256 = "";
    })
  ];

  networking.hosts = {
    "192.168.1.194" = [ "plex-nas" ];
  };

  fileSystems."/var/lib/plex/media-shows" = {
    fsType = "nfs";
    device = "plex-nas:/volume1/media-shows";
    options = nfsOptions ++ [ "ro" ];
  };

  fileSystems."/var/lib/plex/media-channels" = {
    fsType = "nfs";
    device = "plex-nas:/volume1/media-channels";
    options = nfsOptions ++ [ "ro" ];
  };

  fileSystems."/var/lib/plex/media-photos" = {
    fsType = "nfs";
    device = "plex-nas:/volume1/media-photos";
    options = nfsOptions ++ [ "ro" ];
  };

  fileSystems."/var/lib/plex/media-music" = {
    fsType = "nfs";
    device = "plex-nas:/volume1/media-music";
    options = nfsOptions ++ [ "ro" ];
  };

  fileSystems."/var/lib/plex/media-movies" = {
    fsType = "nfs";
    device = "plex-nas:/volume1/media-movies";
    options = nfsOptions ++ [ "ro" ];
  };

  fileSystems."/var/lib/plex/backup" = {
    fsType = "nfs";
    device = "plex-nas:/volume1/app-plex";
    options = nfsOptions;
  };
}
