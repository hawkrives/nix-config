# Beszel agent on potato-bunny (Synology)

The NixOS fleet's beszel agents are declared in `modules/nixos/beszel-agent.nix`.
The Synology is not managed by this flake, so its agent runs as a Docker
container under DSM's Container Manager. This file is the record of that setup.

## Why this agent goes over the LAN, not the tailnet

Every NixOS agent reaches the hub at `http://[fd7a:115c:a1e0::b346:8b63]:8091`
— nutmeg's tailscale ULA. **This one cannot**, and the reason is worth writing
down because the NAS looks like it should work.

potato-bunny holds a tailnet address (`100.111.251.156`) and `tailscale status`
on it is perfectly healthy. But DSM's Tailscale package runs `tailscaled` as an
unprivileged user with no `--tun`, i.e. in userspace networking mode: there is no
`tailscale0` interface and no CGNAT routes in the kernel table. `ip route get
100.70.139.99` on the NAS resolves via the LAN gateway and the connection times
out. The NAS can be *reached* over the tailnet; it cannot *originate* connections
to tailnet addresses. A `network_mode: host` container inherits that exactly.

So this agent uses nutmeg's stable LAN IPv6, `http://[2600:2b00:9b16:6d01::228]:8091`,
and `hosts/nutmeg/beszel.nix` carries a matching firewall rule admitting
**only** the NAS's own stable LAN IPv6 to that port:

```nix
networking.firewall.extraInputRules = ''
  ip6 saddr 2600:2b00:9b16:6d01:9209:d0ff:fe15:4261 tcp dport 8091 accept
'';
```

The rest of the LAN still cannot reach the hub. If DSM's Tailscale is ever moved
to tun mode, this agent can switch to the tailnet address and that firewall rule
can be deleted.

Both addresses now live inside `2600:2b00:9b16:6d01::/64`, a prefix the ISP
delegates to this network rather than something pinned in this repo (nutmeg's
is pinned via `ipv6AcceptRAConfig.Token` in `hosts/nutmeg/hardware.nix`; the
NAS's is EUI-64, derived from its MAC, so it doesn't move the way a DHCP lease
could). **If the ISP ever rotates that `/64`,** both this firewall rule and the
NAS's `HUB_URL` break silently — the agent just retries forever, and the fix
is either to re-derive the new addresses and update both places, or to fall
back to the LAN IPv4 addresses this setup used before 2026-08-13
(`192.168.1.228` for nutmeg, `192.168.1.194` for the NAS, via a matching
`ip saddr` rule instead of `ip6 saddr`).

An IP rather than a hostname, either way: DSM containers cannot reliably resolve
`.local` names — the same wall the Home Assistant container hit.

## Deployment

`/volume1/docker/beszel-agent/docker-compose.yml` on the NAS:

```yaml
services:
  beszel-agent:
    # Locally built: the upstream henrygd/beszel-agent image is distroless and
    # ships no smartctl (and no dynamic linker, so DSM's own smartctl cannot be
    # bind-mounted in either). See image/Dockerfile and docs/beszel-synology.md.
    image: beszel-agent-smart:local
    container_name: beszel-agent
    restart: unless-stopped
    # Host networking so the container uses the NAS's LAN interface directly.
    # (The NAS has no tailscale0 device, so the tailnet address is unreachable.)
    network_mode: host
    # SMART needs to issue raw commands to the drives. SYS_RAWIO covers the eight
    # SATA disks; the NVMe cache device additionally needs SYS_ADMIN, because
    # NVME_IOCTL_ADMIN_CMD is gated on it. SYS_ADMIN is broad — close to root on
    # the host for a network_mode: host container — and is granted deliberately
    # for the full NVMe SMART record (wear level, available spare), not just its
    # temperature. See docs/beszel-synology.md for the narrower alternative.
    cap_add:
      - SYS_RAWIO
      - SYS_ADMIN
    devices:
      - /dev/sata1
      - /dev/sata2
      - /dev/sata3
      - /dev/sata4
      - /dev/sata5
      - /dev/sata6
      - /dev/sata7
      - /dev/sata8
      - /dev/nvme0
      - /dev/nvme0n1
    volumes:
      - /volume1/docker/beszel-agent/data:/var/lib/beszel-agent
      # Read-only mount so the agent can report volume1's disk usage.
      - /volume1:/extra-filesystems/volume1:ro
      # Synthetic hwmon tree presenting the adt7490 board sensors in the layout
      # gopsutil globs for. Synology's driver leaves those attributes on the i2c
      # device node instead of /sys/class/hwmon/hwmonN, and gopsutil's fallback
      # for that layout only fires when the primary glob finds nothing — which
      # k10temp always populates. See docs/beszel-synology.md.
      - /volume1/docker/beszel-agent/sensors:/sensors-sys:ro
    environment:
      HUB_URL: http://[2600:2b00:9b16:6d01::228]:8091
      TOKEN: ${BESZEL_TOKEN}
      KEY: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINIxBO27YxooTl6NWl1Jf8v/AAanacdGhJf9VF1t2yds
      EXTRA_FILESYSTEMS: /extra-filesystems/volume1
      # Overrides the sysfs root for sensor collection only — upstream threads
      # this through a gopsutil context value rather than os.Setenv, so it does
      # not affect the disk or network collectors.
      SYS_SENSORS: /sensors-sys
      # The dashboard temperature is max() across all sensors. That is the CPU
      # today only because nothing else was reported; pin it so the headline
      # number keeps meaning "CPU" now that three board sensors exist.
      PRIMARY_SENSOR: k10temp
      # DSM ships smartctl 6.5, whose --scan globs /dev/discs/disc* (a devfs path
      # that has not existed in years), and DSM names disks /dev/sataN rather than
      # /dev/sdX — so auto-detection finds no disks at all. List them explicitly.
      # The :sat type matters: beszel probes these as SCSI otherwise and its SCSI
      # parser returns state UNKNOWN with no temperature, even though smartctl
      # itself reports fine either way.
      SMART_DEVICES: /dev/sata1:sat,/dev/sata2:sat,/dev/sata3:sat,/dev/sata4:sat,/dev/sata5:sat,/dev/sata6:sat,/dev/sata7:sat,/dev/sata8:sat
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

## Per-drive SMART

Out of the box this agent reported only the mdraid arrays (`md0`–`md6`), because
beszel gets those from `/proc/mdstat` and needs no tooling. Per-drive health —
temperature, power-on hours, reallocated sectors — took three things, each
non-obvious:

**A custom image.** `henrygd/beszel-agent` is distroless: it contains `/agent`
and essentially nothing else. No `smartctl`, and no dynamic linker either, so
bind-mounting DSM's `/usr/bin/smartctl` fails with `exec … no such file or
directory` even though the file is plainly mounted. `image/Dockerfile` next to
the compose file builds alpine + smartmontools + the upstream agent binary:

```bash
cd /volume1/docker/beszel-agent/image
sudo /usr/local/bin/docker build -t beszel-agent-smart:local .
```

Rebuild that to pick up a newer agent — `docker compose pull` will not do it.

`image/Dockerfile` itself lives only on `/volume1`, not in git — this file is
the record of that setup, so it's reproduced here verbatim in case `/volume1`
is ever lost:

```dockerfile
# The upstream henrygd/beszel-agent image is distroless: it contains /agent and
# essentially nothing else — no shell, no libc, no smartctl. SMART monitoring
# needs a smartctl binary, and DSM's own (/usr/bin/smartctl, 6.5) cannot be
# bind-mounted in because the image has no dynamic linker to run it.
#
# So: alpine + a current smartmontools + the upstream agent binary copied in.
# Rebuild this after pulling a newer agent (see docs/beszel-synology.md).
FROM alpine:3
RUN apk add --no-cache smartmontools
COPY --from=henrygd/beszel-agent:latest /agent /agent
ENTRYPOINT ["/agent"]
```

**An explicit device list.** DSM's own smartctl is 6.5, whose `--scan` globs
`/dev/discs/disc*`, a devfs path that has not existed in years; and DSM names
disks `/dev/sataN`, not `/dev/sdX`, so even smartctl 7.5's scan finds nothing.
`SMART_DEVICES` overrides discovery. Without it, no physical disk appears and
nothing is logged to say why.

**The `:sat` type.** Left to itself beszel probes these drives as SCSI, and its
SCSI parser yields `state=UNKNOWN` with `temp=0` — while `smartctl` reports the
drive fine either way, which makes this look like a permissions problem when it
is a parser one. Forcing `:sat` makes all eight report.

The NVMe cache device needs `CAP_SYS_ADMIN` on top of `CAP_SYS_RAWIO`, because
`NVME_IOCTL_ADMIN_CMD` is gated on it (`Permission denied` without). This was
originally declined as too broad for a cache disk, and was later granted anyway
for the full SMART record — wear level and available spare, not just temperature.
It is a real cost: `SYS_ADMIN` on a `network_mode: host` container is close to
root on the host. DSM's own smartctl cannot substitute; version 6.5 fails on this
device outright with `Read NVMe Identify Controller failed: NVMe Status 0x4002`,
where the image's 7.5 succeeds.

Worth knowing if that is ever reconsidered: the *temperature* alone was never
actually blocked. DSM ships `synonvme --temperature-get /dev/nvme0n1`, root-only,
which returns the same figure smartctl does (verified: both 31 °C). A root Task
Scheduler job writing that value into the `sensors/` tree described below would
put NVMe temperature on the chart with no capability grant at all. It buys only
the temperature — no wear or spare — and reintroduces a periodic writer that can
stall silently, which is why it was not the chosen route. Home Assistant's
Synology integration already reports the same value via DSM's API, independently
of beszel.

SMART is polled on `SMART_INTERVAL`, which defaults to **1h** — so after any
change here, expect up to an hour before the hub reflects it, or set
`SMART_INTERVAL: 1m` temporarily while testing.

## Board temperature sensors

Out of the box this agent reported exactly one temperature: `k10temp`, the CPU.
DSM's own Core.System API agrees — its `sys_temp` is the same number from the
same source, so DSM offers no second opinion.

The NAS also carries an `adt7490` fan/thermal controller on i2c at `1-002c` with
three live channels, and beszel could not see any of them. The reason is neither
permissions nor the container: **Synology's driver leaves the hwmon attributes on
the device node** (`/sys/bus/i2c/devices/1-002c/`) instead of symlinking them into
`/sys/class/hwmon/hwmon1/`, which holds only `device`, `power`, `subsystem` and
`uevent` — not even a `name`.

gopsutil has a fallback glob for exactly this layout —
`/class/hwmon/hwmon*/device/temp*_input` — but it runs only when the **primary**
glob returns zero files, and `k10temp` always populates the primary glob. So the
fallback never fires. A natively-installed agent would hit the identical wall;
this is a sysfs-layout problem, not a containerisation one.

The fix is a synthetic hwmon tree at `/volume1/docker/beszel-agent/sensors/`,
mounted read-only at `/sensors-sys` and selected with `SYS_SENSORS`. That variable
overrides the sysfs root for sensor collection *only* — upstream threads it
through a gopsutil context value rather than `os.Setenv`, so it cannot leak into
the disk or network collectors.

```
sensors/class/hwmon/
  hwmon0 -> /sys/class/hwmon/hwmon0          # whichever of the two is k10temp
  hwmon1 -> /sys/class/hwmon/hwmon1          # the other; contributes no temp*_input
  hwmon2/                                     # our labeled view of the adt7490
    name        -> /sys/bus/i2c/devices/1-002c/name
    temp1_input -> /sys/bus/i2c/devices/1-002c/temp1_input
    temp1_label    (regular file: remote1)
    temp2_input -> /sys/bus/i2c/devices/1-002c/temp2_input
    temp2_label    (regular file: local)
    temp3_input -> /sys/bus/i2c/devices/1-002c/temp3_input
    temp3_label    (regular file: remote2)
```

Like `image/Dockerfile`, this tree lives only on `/volume1` and not in git.
Recreate it with:

```bash
mkdir -p /volume1/docker/beszel-agent/sensors/class/hwmon/hwmon2
cd /volume1/docker/beszel-agent/sensors/class/hwmon
ln -s /sys/class/hwmon/hwmon0 hwmon0
ln -s /sys/class/hwmon/hwmon1 hwmon1
cd hwmon2
ln -s /sys/bus/i2c/devices/1-002c/name        name
ln -s /sys/bus/i2c/devices/1-002c/temp1_input temp1_input
ln -s /sys/bus/i2c/devices/1-002c/temp2_input temp2_input
ln -s /sys/bus/i2c/devices/1-002c/temp3_input temp3_input
printf 'remote1\n' > temp1_label
printf 'local\n'   > temp2_label
printf 'remote2\n' > temp3_label
```

**Both class dirs are linked on purpose.** hwmon numbering is probe-order
dependent; linking only today's `k10temp` would silently drop the CPU temperature
if the two ever swapped. Whichever dir actually holds `temp1_input` gets picked up
and named from its own `name` file — and conveniently, the adt7490's class dir has
neither. The adt7490 itself comes in through the number-free i2c path. Nothing
here is generated or refreshed, so there is no script to fail and no value that
can go stale.

**The `_label` files are the point.** gopsutil names a sensor `<name>_<label>`;
with no label all three channels collapse to one key and beszel disambiguates them
by array index (`adt7490`, `adt7490_1`, `adt7490_2`) — opaque, and dependent on
glob order. The labels are the datasheet channel names, giving `adt7490_remote1`,
`adt7490_local` and `adt7490_remote2`. `local` is the chip's own on-die sensor;
where Synology wired the two remote diodes is unknown, and nothing DSM exposes
would say. Compared against the idle SSDs in the same chassis (27–30 °C), all
three channels run 5–18 °C hotter, so none of them is an intake/ambient sensor.

**Do not rename these casually.** A renamed sensor starts a *new* series in the
hub rather than continuing the old one, so the history splits.

`PRIMARY_SENSOR: k10temp` is set alongside. The dashboard temperature is otherwise
`max()` across all sensors, which was the CPU only because nothing else was
reported; pinning it keeps the headline number meaning "CPU".

## Why there is no systemd service tracking

The other agents report systemd services; this one shows none, and that is a
platform limit rather than a misconfiguration. Beszel enumerates units with
`ListUnitsByPatterns`, a D-Bus method added in **systemd 230**. DSM 7.3.2 runs
**systemd 219**:

```
$ sudo dbus-send --system --print-reply --dest=org.freedesktop.systemd1 \
    /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager.ListUnitsByPatterns \
    array:string:"loaded" array:string:"*.service"
Error org.freedesktop.DBus.Error.UnknownMethod: Unknown method
'ListUnitsByPatterns' or interface 'org.freedesktop.systemd1.Manager'.
```

Everything else is present and misleading: plain `ListUnits` works,
`/run/dbus/system_bus_socket` and `/run/systemd/system` both exist, and there are
384 loaded service units. So bind-mounting the D-Bus socket into the container
would connect *successfully* and then report zero services — which looks like a
broken config rather than an unsupported platform. Don't.

Even with enumeration fixed, `CPUUsageNSec`, `TasksCurrent` and `MemoryPeak` do
not exist in systemd 219 either, so per-service metrics would be largely blank;
only `MemoryCurrent` and `ActiveEnterTimestamp` would populate.

Patching a `ListUnits` fallback into the local image was considered and rejected:
it means owning a fork, and turns "rebuild to pick up a newer agent" into "rebase
the patch, then rebuild". Upstream is the right home for that fix.

## Operations

```bash
cd /volume1/docker/beszel-agent
sudo /usr/local/bin/docker compose up -d       # start / apply changes
sudo /usr/local/bin/docker compose pull        # upgrade (but see "Per-drive SMART" — the
                                               # local image needs a rebuild instead)
sudo /usr/local/bin/docker logs beszel-agent   # registration + connection errors
```

The full path is not cosmetic: `sudo`'s `secure_path` on DSM is
`/usr/bin:/bin:/usr/sbin:/sbin` and does not include `/usr/local/bin`, so plain
`sudo docker ...` fails with "command not found" even though `docker` resolves
fine in an interactive root shell (`sudo -i`). `/usr/local/bin/docker` itself is
a symlink that Container Manager's start script creates — it only exists while
the package is running.

Unlike the NixOS agents, this one does **not** upgrade with the fleet — it has to
be pulled by hand. The NixOS agents move to whatever agent version ships with
nixpkgs, but this image bakes in whatever `henrygd/beszel-agent:latest` was at
build time, so after a fleet-wide beszel upgrade, check this agent's reported
version in the hub UI against the others and rebuild it if it has drifted.
