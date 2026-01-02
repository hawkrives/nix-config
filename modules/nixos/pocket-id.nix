{perSystem, ...}: {
  services.pocket-id = {
    enable = true;
    package = perSystem.nixpkgs-unstable.pocket-id;
    environmentFile = "/var/lib/secrets/pocket-id";
    # environmentFile contains the following settings:
    # ENCRYPTION_KEY=$(openssl rand -base64 48)
    settings = {
      APP_URL = "https://id.hawken.is";
    };
  };
}
