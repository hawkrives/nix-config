{...}: {
  imports = [
    ../../../modules/home/home-shared.nix
    ../../../modules/home/git-shared.nix
    ../../../modules/home/jj-shared.nix
    ../../../modules/home/helix-shared.nix
    ../../../modules/home/sqlite-shared.nix
  ];

  services.syncthing = {
    enable = true;
    overrideFolders = true;
    overrideDevices = true;
    guiAddress = "0.0.0.0:8385";

    settings = {
      options.listenAddresses = [
        "tcp://:22001"
        "quic://:22001"
      ];

      devices = {
        long-blippp = {
          id = "BVVVV2C-BN26FQM-OI4GTM5-MSUCFJK-6FDTOJG-MWYO2K4-EFBDOL2-VZG4IQB";
        };
        techcyte-DGQJV434PF = {
          id = "E7TASFG-GOULRTE-VOLVZTN-DOA4BA2-DFBSYR5-KZURLEU-XJAZDKK-QSEQWAL";
        };
      };

      folders = {
        "techcyte" = {
          path = "~/techcyte";
          devices = ["long-blippp" "techcyte-DGQJV434PF"];
        };
      };
    };
  };
}
