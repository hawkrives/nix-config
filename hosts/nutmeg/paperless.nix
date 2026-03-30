{config, ...}: {
  # TODO replace with agenix/sops
  environment.etc."paperless-admin-pass".text = "admin";

  services.paperless = {
    enable = true;
    passwordFile = "/etc/paperless-admin-pass";

    domain = "paperless.vaquita-woodpecker.ts.net";

    consumptionDirIsPublic = true;
    configureTika = true;
    database.createLocally = true;

    # TODO: set mediaDir to NAS folder?
    # mediaDir

    exporter = {
      # TODO: enable once we have the backup share set up
      enable = false;
      # directory = "/mnt/backup/paperless";
    };

    settings = {
      PAPERLESS_CONSUMER_IGNORE_PATTERN = [
        ".DS_STORE/*"
        "desktop.ini"
      ];

      # PAPERLESS_OCR_LANGUAGE = "deu+eng";
      PAPERLESS_OCR_USER_ARGS = {
        optimize = 1;
        pdfa_image_compression = "lossless";
      };
    };
  };

  services.tsnsrv.services.paperless.urlParts.port = config.services.paperless.port;

  networking.firewall.allowedTCPPorts = [config.services.paperless.port];
}
