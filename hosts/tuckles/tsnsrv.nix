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

    # SABnzbd at https://sab.vaquita-woodpecker.ts.net -> 127.0.0.1:6000.
    # (MagicDNS lowercases the node name, so "Sab" → sab.<tailnet>.ts.net.)
    # SAB listens IPv4-only (host = 0.0.0.0), so override the default "localhost"
    # upstream host — it resolves to ::1 first and the v6 dial is refused.
    services.sab.urlParts = {
      host = "127.0.0.1";
      port = config.services.sabnzbd.settings.misc.port;
    };

    # slskd web UI at https://slsk.vaquita-woodpecker.ts.net -> 192.168.15.1:5030.
    # slskd runs *inside* the mullvad netns, so reach it on the netns bridge addr
    # (the DNAT port-map is PREROUTING-only; localhost won't enter the namespace).
    services.slsk.urlParts = {
      host = "192.168.15.1";
      port = config.services.slskd.settings.web.port;
    };
  };
}
