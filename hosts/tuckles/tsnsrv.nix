{ config, ... }:
{
  services.tsnsrv = {
    enable = true;

    defaults = {
      # Reuse the existing tailscale OAuth client secret (scoped to
      # tag:container,tag:servarr). tsnsrv reads it via systemd LoadCredential as
      # root, so the root-owned agenix secret needs no permission changes.
      authKeyPath = config.age.secrets.tailscale-authkey-tuckles.path;
      tags = [
        "tag:container"
        "tag:servarr"
      ];
      ephemeral = false; # the reused OAuth key is ?ephemeral=false
      urlParts.host = "localhost";
    };

    # qui at https://qui.vaquita-woodpecker.ts.net -> localhost:7476
    services.qui.urlParts.port = config.services.qui.settings.port;
  };
}
