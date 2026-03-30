{config, ...}: {
  services.tsnsrv.services.peertube.urlParts.host = "127.0.0.1";
  services.tsnsrv.services.peertube.urlParts.port = config.services.peertube.listenHttp;

  services.peertube = {
    enable = true;
    listenWeb = 443;
    # configureNginx = true;
    localDomain = "peertube.vaquita-woodpecker.ts.net";
    enableWebHttps = true;

    redis.createLocally = true;
    database.createLocally = true;

    secrets.secretsFile = "/etc/peertube/secret";

    # # enable once we have soops/agenix set up
    # secrets.smtpPasswordFile = "/run/secrets/peertube-smtp-password";
    # smtp = {
    #   createLocally = false;
    #   hostname = "smtp.fastmail.com";
    #   port = 465;
    #   from = "your-address@fastmail.com";
    #   username = "your-address@fastmail.com";
    #   tls = true;
    # };

    settings = {
      instance.name = "vidz-bop";
      # whisper is broken (2026-03-30) due to a python dependency on 26.05
      # video_transcription.enabled = true;
    };
  };

  # TODO: replace with age
  environment.etc."peertube/secret".text = "8f8fed4ded8dfa7c857e962e6855ae248ebc38ef7d3cf164f8561eed845309f7";

  networking.firewall.allowedTCPPorts = [23357];
}
