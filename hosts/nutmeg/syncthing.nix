{...}: {
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    guiAddress = "0.0.0.0:8384";

    settings = {
      devices = {
        long-blippp = {id = "BVVVV2C-BN26FQM-OI4GTM5-MSUCFJK-6FDTOJG-MWYO2K4-EFBDOL2-VZG4IQB";};
        techcyte-DGQJV434PF = {id = "E7TASFG-GOULRTE-VOLVZTN-DOA4BA2-DFBSYR5-KZURLEU-XJAZDKK-QSEQWAL";};
      };

      folders = {
        "~/paperless" = {devices = ["long-blippp" "techcyte-DGQJV434PF"];};
        "~/icloud" = {devices = ["long-blippp" "techcyte-DGQJV434PF"];};
      };
    };
  };

  # techcyte user's home-manager syncthing instance (see users/techcyte.nix)
  # 8385 = techcyte GUI, 22001 = techcyte sync protocol
  networking.firewall = {
    allowedTCPPorts = [8384 8385 22001];
    allowedUDPPorts = [22001];
  };
}
