# nix-config

Personal NixOS / nix-darwin fleet (nutmeg, tuckles, pantry, bigpond, …).

## Deploying

This repo uses [`nh`](https://github.com/nix-community/nh), **not** `nixos-rebuild` directly:

```bash
nh os switch      # build + activate the current host's flake config
nh os boot        # stage for next boot only
nh home switch    # standalone Home Manager configs
```

### Remote hosts

Deploy to another host over SSH with `--target-host user@host`. The activation step
needs root on the *remote*, and there's no interactive prompt over SSH, so pass
`-e passwordless` (`--elevation-strategy`) — the remote admin users have NOPASSWD sudo:

```bash
nh os switch --target-host haru@tuckles.local --hostname tuckles .#tuckles -e passwordless
nh os switch --target-host nix@pantry.local  --hostname pantry  .#pantry  -e passwordless
```

Add `--build-host user@host` to build on the remote instead of locally.


## Secrets

Secrets are age-encrypted with ragenix. To add one:

```bash
cd ./secrets
# declare the secret in secrets.nix, then
ragenix -e $name.age
```

See [`secrets/README.md`](secrets/README.md) for the full workflow (recipients, rekeying,
consuming a secret on a host, env-file vs bare conventions).

## Docs

- [`docs/home-assistant.md`](docs/home-assistant.md) — Home Assistant on nutmeg: **drive it
  through its API (with the `hass-token` secret), not by hand-editing `.storage`**, plus
  container/systemd and networking gotchas.
