{...}: {
  environment.etc."paperless-admin-pass".text = "admin";
  services.paperless = {
    enable = true;
    consumptionDirIsPublic = true;
    # address = "0.0.0.0";
    # TODO: expose via tailscale;
    # TODO: do not bind to 0.0.0.0
    passwordFile = "/etc/paperless-admin-pass";
    address = "0.0.0.0";
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
      # PAPERLESS_URL = "https://paperless.example.com";
      PAPERLESS_URL = "http://nutmeg.local:28981";
      # PAPERLESS_URL = "http://192.168.1.228:28981";
    };
  };

  networking.firewall.allowedTCPPorts = [28981];
}
