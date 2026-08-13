{ config, ... }:
{
  # Beszel — lightweight fleet monitoring. This is the hub: the web UI plus the
  # PocketBase database that holds every agent's metric history.
  #
  # Agents connect *outbound* over WebSocket (see modules/nixos/beszel-agent.nix),
  # so the hub has to be reachable from the other hosts — ::1 won't do.
  # A wildcard bind is safe here: tailscale0 is a trusted interface on every
  # host, so tailnet peers reach it that way. The LAN firewall opens 8091 to
  # exactly one host below (potato-bunny) as a single documented exception;
  # every other LAN address still sees nothing.
  services.beszel.hub = {
    enable = true;
    # The listener is dual-stack regardless of what's written here — nixpkgs
    # builds --http='${host}:${port}', and ss shows *:8091 on the IPv6 side
    # with nothing on IPv4. "[::]" just says what actually happens.
    host = "[::]";
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

  # https://beszel.<tailnet>.ts.net -> [::1]:8091. The loopback literal rather
  # than the "localhost" default, so this doesn't depend on resolver ordering.
  # The brackets are required: tsnsrv's toURL interpolates `host` straight into
  # a URL ("${protocol}://${host}:${port}") without adding them itself, so an
  # unbracketed "::1" would render the invalid "http://::1:8091".
  services.tsnsrv.services.beszel.urlParts = {
    host = "[::1]";
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
  # 2600:2b00:9b16:6d01:9209:d0ff:fe15:4261 is the NAS's stable LAN IPv6
  # (EUI-64, derived from its MAC — it doesn't move the way a DHCP lease
  # could). It lives inside 2600:2b00:9b16:6d01::/64, which is delegated to
  # this network by the ISP rather than pinned anywhere in this repo: if the
  # ISP ever rotates that /64, this rule and the NAS's HUB_URL both break
  # silently (the agent just retries forever), and the fallback is to revert
  # both to the LAN IPv4 addresses (nutmeg's own LAN address has the same
  # rotation risk — see hardware.nix).
  networking.firewall.extraInputRules = ''
    ip6 saddr 2600:2b00:9b16:6d01:9209:d0ff:fe15:4261 tcp dport ${toString config.services.beszel.hub.port} accept
  '';
}
