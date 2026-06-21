{ config, ... }:
{
  # qui — an alternate web UI for qBittorrent (autobrr/qui). It runs in the host
  # namespace (it's just a UI). qBittorrent lives in the mullvad netns; from the
  # host it's reachable at the namespace bridge address 192.168.15.1:6001 (the
  # mullvad namespaceAddress) — NOT localhost, because the port-forward is a
  # PREROUTING DNAT and host-local traffic skips it. So in qui's UI, add the
  # instance as http://192.168.15.1:6001 (no credentials needed).
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
