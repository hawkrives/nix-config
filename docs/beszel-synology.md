# Beszel agent on potato-bunny (Synology)

The NixOS fleet's beszel agents are declared in `modules/nixos/beszel-agent.nix`.
potato-bunny isn't NixOS, so its agent is a unit in the potato-bunny system
layer, `beszel-agent.service` in `hosts/potato-bunny/system.nix`, deployed with
`mise run potato-bunny:ask` and re-applied at every boot.

## This agent talks to the hub over loopback

The hub runs on this NAS (`hosts/potato-bunny/beszel-hub.nix`), so this agent
reaches it at `http://[::1]:8091`. Every NixOS agent reaches it at
`http://[fd7a:115c:a1e0:ab12:4843:cd96:626f:fb9c]:8091`, the NAS's tailscale
ULA.

## Deployment

The unit runs `pkgs.beszel`'s `beszel-agent` as root, bounded by
`CapabilityBoundingSet` to `CAP_SYS_RAWIO CAP_SYS_ADMIN CAP_DAC_READ_SEARCH
CAP_DAC_OVERRIDE`, with nixpkgs' smartmontools on its `PATH`. Its environment:

| Variable | Value | Why |
| --- | --- | --- |
| `HUB_URL` | `http://[::1]:8091` | the hub runs on this NAS — see above |
| `KEY` | the hub's public key | same value as `modules/nixos/beszel-agent.nix` |
| `TOKEN` | from `/volume1/@appdata/nix-system/secrets/beszel-agent.env` | see below |
| `DATA_DIR` | `/volume1/docker/beszel-agent/data` | holds `fingerprint`, the agent's identity in the hub |
| `EXTRA_FILESYSTEMS` | `/volume1` | report the data volume's usage |
| `SYS_SENSORS` | `/volume1/docker/beszel-agent/sensors` | see "Board temperature sensors" |
| `PRIMARY_SENSOR` | `k10temp` | keep the headline temperature meaning "CPU" |
| `SMART_DEVICES` | `/dev/sata1:sat,…,/dev/sata8:sat` | see "Per-drive SMART" |

The hub recognises an agent by the `fingerprint` file in `DATA_DIR`. Don't
delete or move it without its contents: a new fingerprint means a new system in
the hub, and the old one's history stays behind.

`TOKEN` is the hub's **universal** registration token (Hub UI → Settings →
Tokens), shared with every NixOS agent, where it lives in
`secrets/beszel-token.age`. agenix doesn't run on DSM, so on the NAS it sits in
a root-only (`0400`, in a `0700` directory) file, written once by hand:

```bash
sudo install -d -m 0700 /volume1/@appdata/nix-system/secrets
read -rs TOKEN    # paste the token; it isn't echoed, logged or put on a command line
printf 'TOKEN=%s\n' "$TOKEN" |
  sudo sh -c 'umask 277; cat > /volume1/@appdata/nix-system/secrets/beszel-agent.env'
unset TOKEN
```

`/volume1/@appdata` is not an SMB share, unlike `/volume1/nix`. The unit has no
`-` on `EnvironmentFile`, so without this file the agent refuses to start
rather than run unregistered.

## Per-drive SMART

Out of the box this agent reported only the mdraid arrays (`md0`–`md6`), because
beszel gets those from `/proc/mdstat` and needs no tooling. Per-drive health —
temperature, power-on hours, reallocated sectors — took three things, each
non-obvious:

**A current smartctl.** DSM's own is 6.5; the unit puts nixpkgs'
smartmontools first on `PATH`.

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
It is a real cost: `SYS_ADMIN` is close to root, and the agent already runs as
root. DSM's own smartctl cannot substitute; version 6.5 fails on this
device outright with `Read NVMe Identify Controller failed: NVMe Status 0x4002`,
where nixpkgs' 7.5 succeeds.

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
`SMART_INTERVAL=1m` in the unit temporarily while testing.

## Board temperature sensors

Out of the box this agent reported exactly one temperature: `k10temp`, the CPU.
DSM's own Core.System API agrees — its `sys_temp` is the same number from the
same source, so DSM offers no second opinion.

The NAS also carries an `adt7490` fan/thermal controller on i2c at `1-002c` with
three live channels, and beszel could not see any of them. The reason is neither
permissions nor how the agent runs: **Synology's driver leaves the hwmon attributes on
the device node** (`/sys/bus/i2c/devices/1-002c/`) instead of symlinking them into
`/sys/class/hwmon/hwmon1/`, which holds only `device`, `power`, `subsystem` and
`uevent` — not even a `name`.

gopsutil has a fallback glob for exactly this layout —
`/class/hwmon/hwmon*/device/temp*_input` — but it runs only when the **primary**
glob returns zero files, and `k10temp` always populates the primary glob. So the
fallback never fires. A natively-installed agent would hit the identical wall;
this is a sysfs-layout problem.

The fix is a synthetic hwmon tree at `/volume1/docker/beszel-agent/sensors/`,
selected with `SYS_SENSORS`. That variable
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

This tree lives only on `/volume1` and not in git.
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
384 loaded service units. The agent connects to the system bus *successfully*
and then reports zero services, logging one `ERROR Error listing systemd service
units … ListUnitsByPatterns` per start — which looks like a broken config
rather than an unsupported platform.

Even with enumeration fixed, `CPUUsageNSec`, `TasksCurrent` and `MemoryPeak` do
not exist in systemd 219 either, so per-service metrics would be largely blank;
only `MemoryCurrent` and `ActiveEnterTimestamp` would populate.

Patching a `ListUnits` fallback into the agent was considered and rejected: it
means owning a fork that has to be rebased on every fleet beszel upgrade.
Upstream is the right home for that fix.

## Operations

```bash
mise run potato-bunny:ask                       # deploy a change (from nutmeg)
systemctl status beszel-agent                   # on the NAS
sudo journalctl -u beszel-agent                 # registration + connection errors
```

The agent upgrades with the fleet: it's whatever `pkgs.beszel` is in this
flake's nixpkgs, same as the NixOS agents.

`/volume1/docker/beszel-agent/` also holds an unused `docker-compose.yml`,
`.env` and `image/` from an earlier Docker-based agent; only `data/` and
`sensors/` are in use.
