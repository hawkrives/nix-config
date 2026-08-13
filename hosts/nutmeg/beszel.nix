{ config, ... }:
{
  # Beszel — lightweight fleet monitoring. This is the hub: the web UI plus the
  # PocketBase database that holds every agent's metric history.
  #
  # Agents connect *outbound* over WebSocket (see modules/nixos/beszel-agent.nix),
  # so the hub has to be reachable from the other hosts — 127.0.0.1 won't do.
  # 0.0.0.0 is safe here: the LAN firewall never opens 8091, and tailscale0 is a
  # trusted interface on every host, so in practice only tailnet peers reach it.
  services.beszel.hub = {
    enable = true;
    host = "0.0.0.0";
    # 8091, not beszel's default 8090: scanservjs already holds 8090 on this
    # host (see scanner.nix). Don't "fix" this back to 8090.
    port = 8091;
  };

  # https://beszel.<tailnet>.ts.net -> 127.0.0.1:8091. 127.0.0.1 rather than the
  # "localhost" default: the hub's listener is IPv4-only, and localhost resolves
  # to ::1 first, which it refuses (same trap as bazarr and sabnzbd).
  services.tsnsrv.services.beszel.urlParts = {
    host = "127.0.0.1";
    port = config.services.beszel.hub.port;
  };
}
