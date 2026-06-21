{ config, ... }:
{
  # qui — an alternate web UI for qBittorrent (autobrr/qui). It runs in the host
  # namespace (it's just a UI) and connects to qBittorrent's WebUI, which is
  # forwarded out of the mullvad netns to 127.0.0.1:6001. Add that instance from
  # qui's own web UI after first start.
  services.qui = {
    enable = true;
    openFirewall = true;
    secretFile = config.age.secrets.qui-session-secret.path;
    settings = {
      host = "0.0.0.0"; # reachable on the LAN / tailscale (tuckles.local:7476)
      port = 7476;
    };
  };
}
