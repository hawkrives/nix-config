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

in {
  services.plex = {
    enable = true;
    package = pkgs-unstable.plex;
    group = "servarr";
    openFirewall = true;
  };

  services.tautulli = {
    enable = true;
  };

  users.groups.servarr = { gid = 1050; };
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
        rev = "bb684a2299d06b1377b4d3e1c81dff417ce4e9de";
        sha256 = "PtW8I2iloD3SohPPo12zDSsFg9rskNj1W15bg0DA/BY=";
      };
    })
  ];

  services.plex.extraScanners = [
    (pkgs.fetchFromGitHub {
      owner = "ZeroQI";
      repo = "Absolute-Series-Scanner";
      rev = "7121c1d744fcbb3ef58bf5fcb0d157b847e7cfd5";
      sha256 = "EIXOP4Rhmfw5VYSLANFZoIyYIJ4Gmm67g66xdthLwwU=";
    })
  ];

  networking.hosts = {
    "192.168.1.194" = ["plex-nas"];
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
