# Disabled hosts

Host configurations parked out of the build. Blueprint discovers hosts by reading
the directories directly under `hosts/`, and throws on any directory there that
has no recognised configuration file — so a host is disabled by moving its
directory *out* of `hosts/` rather than by renaming it in place or adding a flag.

Nothing in here is evaluated: no `nixosConfigurations` entry, no `nix flake check`
build, no `flake.lock` update breakage.

## Currently parked

### `bigpond` — 2019 T2 Intel MacBook Pro, remote builder

Parked 2026-08-13: the machine is dead. Its configuration is intact and was
evaluating cleanly when it was parked.

Re-enable with:

```bash
mv hosts-disabled/bigpond hosts/bigpond
```

Two things to know before deploying it again, both of which cost real time to
rediscover:

- **Always pass `--build-host pinklady@bigpond.local`.** bigpond runs a T2 kernel
  (`linux-t2`) that it fetches from `cache.soopy.moe`, a substituter configured
  only on bigpond itself. Building its closure anywhere else — including nutmeg —
  compiles that kernel from source, which takes hours:

  ```bash
  nh os switch .#bigpond --target-host pinklady@bigpond.local \
    --build-host pinklady@bigpond.local --hostname bigpond -e passwordless
  ```

- **It carries staged, never-deployed beszel configuration.** It picks up the
  monitoring agent from `modules/nixos/host-server.nix`, and
  `hosts-disabled/bigpond/configuration.nix` enables `smartmon` for its NVMe. That
  combination has never run on this host. On the first deploy, confirm SMART data
  actually reaches the hub — the module's udev rule
  (`KERNEL=="nvme[0-9]*", GROUP="disk"`) does not apply to devices that already
  exist, so it may need:

  ```bash
  sudo udevadm control --reload && sudo udevadm trigger
  sudo systemctl restart beszel-agent
  ```

  See `docs/beszel-synology.md` for how the rest of the monitoring fits together.

Its secrets are untouched: `secrets/secrets.nix` still lists bigpond's host key as
a recipient for `tailscale-authkey-bigpond.age` and `beszel-token.age`, so nothing
needs rekeying to bring it back.
