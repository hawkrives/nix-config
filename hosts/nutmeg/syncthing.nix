{...}: {
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    guiAddress = "0.0.0.0:8384";

    settings = {
      devices = {
        long-blippp = {id = "BVVVV2C-BN26FQM-OI4GTM5-MSUCFJK-6FDTOJG-MWYO2K4-EFBDOL2-VZG4IQB";};
        techcyte-DGQJV434PF = {id = "E7TASFG-GOULRTE-VOLVZTN-DOA4BA2-DFBSYR5-KZURLEU-XJAZDKK-QSEQWAL";};
        steamdeck = {id = "2G6JUBG-C3ZJDCL-YRVELTQ-4O746N2-R4XSROH-RC7U4QF-ORZZFMA-QCZFKQH";};
        # The NAS (SynoCommunity syncthing package, data on /volume2/syncthing).
        # Paired so nutmeg and potato-bunny reconcile ~/icloud directly instead
        # of only converging indirectly via long-blippp — both currently serve
        # the same folder id, and letting them drift would surface as conflict
        # files. Transitional: the NAS is taking over as the always-on node.
        potato-bunny = {id = "MSC3KN2-QIEXO22-5MWI2B4-FZWJIDB-T7JLZCV-CIVSD5R-NHKDMI6-KZVQOQH";};
      };

      folders = {
        "~/paperless" = {devices = ["long-blippp" "techcyte-DGQJV434PF"];};
        "~/icloud" = {devices = ["long-blippp" "techcyte-DGQJV434PF" "potato-bunny"];};
        # "games" = {devices = ["steamdeck"c]}
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
