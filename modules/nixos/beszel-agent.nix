# Beszel monitoring agent — enabled fleet-wide via host-server.nix, so every
# NixOS server reports to the hub on nutmeg (hosts/nutmeg/beszel.nix).
#
# WebSocket mode: the agent dials *out* to the hub and self-registers with a
# universal token, so nothing needs opening in the firewall — 45876 is not in
# any allowedTCPPorts. It's not port-less, though: the journal shows the agent
# binding an SSH server on :45876 at startup and stopping it once the
# WebSocket connects, and it presumably re-binds it during a hub outage. It's
# just never reachable from outside, so it doesn't matter. HUB_URL is nutmeg's
# tailscale IP rather than a name because it has
# to resolve identically everywhere: nutmeg itself runs --accept-dns=false so it
# can't resolve MagicDNS names, and the Synology's Docker agent can't resolve
# .local. The address is nutmeg's tailnet ULA rather than its CGNAT IPv4 —
# stable per-node either way, and holds no secret.
#
# SMART monitoring is deliberately NOT enabled here — it loosens the systemd
# sandbox, so it's opted into per host (nutmeg, bigpond) on real hardware only.
{ config, ... }:
{
  age.secrets.beszel-token.file = ../../secrets/beszel-token.age;

  services.beszel.agent = {
    enable = true;
    environment = {
      HUB_URL = "http://[fd7a:115c:a1e0::b346:8b63]:8091";

      # The hub's public key. Required even in WebSocket mode — the agent
      # refuses to start without it ("no key provided"), because TOKEN only
      # authorizes registration while KEY is what authenticates the hub to the
      # agent. It is the public half of /var/lib/beszel-hub/beszel_data/id_ed25519
      # on nutmeg (the hub also shows it on its Add System dialog), so it is not
      # a secret and belongs here rather than in agenix. Regenerating the hub's
      # keypair means updating this value — and the Synology compose file
      # carries its own copy of it (docs/beszel-synology.md, and the live
      # docker-compose.yml on the NAS), so that needs updating too.
      KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINIxBO27YxooTl6NWl1Jf8v/AAanacdGhJf9VF1t2yds";
    };
    environmentFile = config.age.secrets.beszel-token.path;
  };
}
