{config, ...}: {
  # Superuser password is decrypted to /run/agenix/paperless-admin-pass and read
  # by systemd LoadCredential (as root) when starting the paperless service.
  age.secrets.paperless-admin-pass.file = ../../secrets/paperless-admin-pass.age;

  services.paperless = {
    enable = true;
    passwordFile = config.age.secrets.paperless-admin-pass.path;

    domain = "paperless.vaquita-woodpecker.ts.net";

    consumptionDirIsPublic = true;

    # Tika + gotenberg convert office documents (docx, html, etc.) to PDF, which
    # drags in LibreOffice (~1.4 GB) and Chromium (~690 MB). We only feed PDFs
    # and scans to paperless, so leave it off.
    configureTika = false;

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

      # Setting this trims tesseract's trained data to just these languages
      # (+ eng/osd/equ, always included), instead of shipping all ~130 (~1 GB).
      PAPERLESS_OCR_LANGUAGE = "eng+jpn";
      # Scans arrive as 300dpi colour JPEGs. Lossless storage of those produces
      # very large archive files, so re-encode as JPEG inside the PDF/A.
      PAPERLESS_OCR_USER_ARGS = {
        optimize = 1;
        pdfa_image_compression = "jpeg";
      };

      # Feeder scans can arrive rotated; orient them from detected text.
      PAPERLESS_OCR_ROTATE_PAGES = true;
    };
  };

  services.tsnsrv.services.paperless.urlParts.port = config.services.paperless.port;
  services.tsnsrv.services.paperless.urlParts.host = config.services.paperless.address;

  networking.firewall.allowedTCPPorts = [config.services.paperless.port];
}
