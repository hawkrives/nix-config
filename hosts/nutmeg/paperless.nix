{config, ...}: {
  # Superuser password is decrypted to /run/agenix/paperless-admin-pass and read
  # by systemd LoadCredential (as root) when starting the paperless service.
  age.secrets.paperless-admin-pass.file = ../../secrets/paperless-admin-pass.age;

  services.paperless = {
    enable = true;
    passwordFile = config.age.secrets.paperless-admin-pass.path;

    domain = "paperless-1.vaquita-woodpecker.ts.net";

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
  services.tsnsrv.services.paperless.urlParts.host = config.services.paperless.address;

  networking.firewall.allowedTCPPorts = [config.services.paperless.port];
}
