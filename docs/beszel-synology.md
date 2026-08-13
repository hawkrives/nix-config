# Beszel agent on potato-bunny (Synology)

The NixOS fleet's beszel agents are declared in `modules/nixos/beszel-agent.nix`.
The Synology is not managed by this flake, so its agent runs as a Docker
container under DSM's Container Manager. This file is the record of that setup.

## Why this agent goes over the LAN, not the tailnet

Every NixOS agent reaches the hub at `http://100.70.139.99:8091` — nutmeg's
tailscale address. **This one cannot**, and the reason is worth writing down
because the NAS looks like it should work.

potato-bunny holds a tailnet address (`100.111.251.156`) and `tailscale status`
on it is perfectly healthy. But DSM's Tailscale package runs `tailscaled` as an
unprivileged user with no `--tun`, i.e. in userspace networking mode: there is no
`tailscale0` interface and no CGNAT routes in the kernel table. `ip route get
100.70.139.99` on the NAS resolves via the LAN gateway and the connection times
out. The NAS can be *reached* over the tailnet; it cannot *originate* connections
to tailnet addresses. A `network_mode: host` container inherits that exactly.

So this agent uses nutmeg's LAN address, `http://192.168.1.228:8091`, and
`hosts/nutmeg/beszel.nix` carries a matching firewall rule admitting **only**
192.168.1.194 to that port:

```nix
networking.firewall.extraInputRules = ''
  ip saddr 192.168.1.194 tcp dport 8091 accept
'';
```

The rest of the LAN still cannot reach the hub. If DSM's Tailscale is ever moved
to tun mode, this agent can switch to the tailnet address and that firewall rule
can be deleted.

An IP rather than a hostname, either way: DSM containers cannot reliably resolve
`.local` names — the same wall the Home Assistant container hit.

## Deployment

`/volume1/docker/beszel-agent/docker-compose.yml` on the NAS:

```yaml
services:
  beszel-agent:
    image: henrygd/beszel-agent:latest
    container_name: beszel-agent
    restart: unless-stopped
    network_mode: host
    volumes:
      - /volume1/docker/beszel-agent/data:/var/lib/beszel-agent
      - /volume1:/extra-filesystems/volume1:ro
    environment:
      HUB_URL: http://192.168.1.228:8091
      TOKEN: ${BESZEL_TOKEN}
      KEY: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINIxBO27YxooTl6NWl1Jf8v/AAanacdGhJf9VF1t2yds
      EXTRA_FILESYSTEMS: /extra-filesystems/volume1
```

`BESZEL_TOKEN` comes from `/volume1/docker/beszel-agent/.env`, which holds the
hub's **universal** registration token (Hub UI → Settings → Tokens). That token is
shared with every NixOS agent, where it lives in `secrets/beszel-token.age`. It is
deliberately not written down here.

Bind mounts must live under `/volume1`; DSM's Docker rejects paths outside it.

Container Manager (the DSM package that owns `dockerd`) was turned off when this
agent was set up; it was started with `synopkg start ContainerManager`, which
also marks it to auto-start on boot. If `docker ps` ever comes back empty after
a NAS reboot, check `synopkg status ContainerManager` before suspecting the
agent itself.

## Operations

```bash
cd /volume1/docker/beszel-agent
sudo /usr/local/bin/docker compose up -d       # start / apply changes
sudo /usr/local/bin/docker compose pull        # upgrade the agent
sudo /usr/local/bin/docker logs beszel-agent   # registration + connection errors
```

The full path is not cosmetic: `sudo`'s `secure_path` on DSM is
`/usr/bin:/bin:/usr/sbin:/sbin` and does not include `/usr/local/bin`, so plain
`sudo docker ...` fails with "command not found" even though `docker` resolves
fine in an interactive root shell (`sudo -i`). `/usr/local/bin/docker` itself is
a symlink that Container Manager's start script creates — it only exists while
the package is running.

Unlike the NixOS agents, this one does **not** upgrade with the fleet — it has to
be pulled by hand.
