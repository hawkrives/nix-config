{...}: {
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    guiAddress = "0.0.0.0:8384";

    settings = {
      devices = {
        long-blippp = {
          id = "BVVVV2C-BN26FQM-OI4GTM5-MSUCFJK-6FDTOJG-MWYO2K4-EFBDOL2-VZG4IQB";
          # autoAcceptFolders = true;
        };
      };

      folders = {
        "~/paperless" = {devices = ["long-blippp"];};
        "~/icloud" = {devices = ["long-blippp"];};
      };
    };
  };

  networking.firewall.allowedTCPPorts = [8384];
}
