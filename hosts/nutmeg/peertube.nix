{
  config,
  lib,
  ...
}: let
  cfg = config.services.peertube;
in {
  services.tsnsrv.services.peertube.urlParts.host = "127.0.0.1";
  services.tsnsrv.services.peertube.urlParts.port = config.services.peertube.listenHttp;

  services.peertube = {
    # disable until we get the media off of nutmeg
    # enable = true;

    listenWeb = 443;
    # configureNginx = true;
    localDomain = "peertube.vaquita-woodpecker.ts.net";
    enableWebHttps = true;

    redis.createLocally = true;
    database.createLocally = true;

    # Signing secret, decrypted to /run/agenix/peertube-secret. PeerTube reads
    # this as its own service user, so the secret is owned by that user (see
    # age.secrets below). Both are guarded on `enable` because the peertube user
    # only exists when the service is on.
    secrets.secretsFile = lib.mkIf cfg.enable config.age.secrets.peertube-secret.path;

    # # enable once we have the smtp secret set up
    # secrets.smtpPasswordFile = config.age.secrets.peertube-smtp-password.path;
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
      # whisper is broken (2026-03-30) due to a python dependency on nixos 26.05
      # video_transcription.enabled = true;
    };
  };

  # Owned by the peertube user because the service reads the file directly (not
  # via systemd LoadCredential). Guarded on `enable`: the peertube user is only
  # created when the service is enabled, so activation can't chown to it before.
  age.secrets.peertube-secret = lib.mkIf cfg.enable {
    file = ../../secrets/peertube-secret.age;
    owner = cfg.user;
    group = cfg.group;
  };

  networking.firewall.allowedTCPPorts = [23357];
}
