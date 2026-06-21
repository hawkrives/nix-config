{ config, ... }:
{
  services.tsnsrv = {
    enable = true;

    defaults = {
      # Same OAuth client as the main tailscale node, but the *bare* secret
      # (no ?ephemeral query) — tsnsrv mints its own key via the OAuth token
      # endpoint and the query suffix would 401 it. tsnsrv reads it via systemd
      # LoadCredential as root, so the root-owned agenix secret needs no perms.
      authKeyPath = config.age.secrets.tsnsrv-authkey-tuckles.path;
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
