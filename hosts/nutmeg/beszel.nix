{ config, ... }:
{
  # Beszel — lightweight fleet monitoring. This is the hub: the web UI plus the
  # PocketBase database that holds every agent's metric history.
  #
  # Agents connect *outbound* over WebSocket (see modules/nixos/beszel-agent.nix),
  # so the hub has to be reachable from the other hosts — 127.0.0.1 won't do.
  # 0.0.0.0 is safe here: tailscale0 is a trusted interface on every host, so
  # tailnet peers reach it that way. The LAN firewall opens 8091 to exactly one
  # host below (potato-bunny) as a single documented exception; every other LAN
  # address still sees nothing.
  services.beszel.hub = {
    enable = true;
    host = "0.0.0.0";
    # 8091, not beszel's default 8090: scanservjs already holds 8090 on this
    # host (see scanner.nix). Don't "fix" this back to 8090.
    #
    # Changing this port is not just a one-liner: HUB_URL in
    # modules/nixos/beszel-agent.nix and the Synology compose file
    # (docs/beszel-synology.md, and the live copy on the NAS) hardcode 8091
    # too and would need updating in step, or the whole fleet silently stops
    # reporting (agents just retry forever).
    port = 8091;
  };

  # https://beszel.<tailnet>.ts.net -> 127.0.0.1:8091. 127.0.0.1 rather than the
  # "localhost" default: the hub's listener is IPv4-only, and localhost resolves
  # to ::1 first, which it refuses (same trap as bazarr and sabnzbd).
  services.tsnsrv.services.beszel.urlParts = {
    host = "127.0.0.1";
    port = config.services.beszel.hub.port;
  };

  # SMART health and drive temps for the Mac Mini's SATA SSD. This is opt-in per
  # host because it grants the agent CAP_SYS_RAWIO/CAP_SYS_ADMIN and drops
  # NoNewPrivileges + PrivateDevices — worth it on real hardware, pointless on
  # the tuckles/pantry VMs.
  services.beszel.agent.smartmon.enable = true;

  # potato-bunny (the Synology) can't reach the hub over the tailnet: DSM's
  # Tailscale package runs tailscaled unprivileged with no tun device, so the NAS
  # has a tailnet address but no route to one. It talks to the hub over the LAN
  # instead, which means opening 8091 — but only to that one host, so the rest of
  # the LAN still sees nothing. Every other agent keeps using the tailnet.
  #
  # 192.168.1.194 is a router DHCP reservation for the NAS's MAC, not pinned
  # anywhere in this repo (nutmeg's own LAN address is the same story — see
  # hardware.nix). If either reservation moves, this rule silently starts
  # admitting whoever inherits .194, and the NAS agent silently goes stale
  # pointing at whoever inherits nutmeg's old address.
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.1.194 tcp dport ${toString config.services.beszel.hub.port} accept
  '';
}
