{perSystem, ...}: {
  environment.etc."paperless-admin-pass".text = "admin";
  services.paperless = {
    enable = true;
    package = perSystem.nixpkgs-unstable.paperless-ngx;
    consumptionDirIsPublic = true;
    passwordFile = "/etc/paperless-admin-pass";

    # TODO: expose via tailscale; do not bind to 0.0.0.0
    # address = "0.0.0.0";

    # TODO: migrate data to postgres
    # database.createLocally = true;

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

      PAPERLESS_URL = "https://paperless.vaquita-woodpecker.ts.net";
      # PAPERLESS_URL = "http://nutmeg.local:28981";
      # PAPERLESS_URL = "http://192.168.1.228:28981";
    };
  };

  # networking.firewall.allowedTCPPorts = [28981];
}
