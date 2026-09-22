# nix-config

Personal NixOS / nix-darwin fleet (nutmeg, tuckles, pantry, …).

Hosts parked out of the build live in [`hosts-disabled/`](hosts-disabled/README.md) —
currently `bigpond`, whose machine is dead.

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


## Building nutmeg without flakes (nixtamal, experimental)

nutmeg can also be built from [`default.nix`](default.nix), with its inputs
pinned by [nixtamal](https://nixtamal.toast.al/) instead of `flake.lock`. This
is a **parallel** path, not a replacement — the flake still owns tuckles,
pantry and Techcyte, and both paths build nutmeg from the same files under
`hosts/nutmeg/` and `modules/`.

```bash
mise run nutmeg:tamal          # build nutmeg the non-flake way
ACTION=switch mise run nutmeg:tamal

nix-build -A toplevel          # same thing, without nh
nh os switch --file . nixosConfigurations.nutmeg --hostname nutmeg
```

Updating inputs (the `nix flake update` equivalent):

```bash
mise run tamal:status          # which inputs have drifted
mise run tamal:refresh         # re-resolve every fresh-cmd, relock
mise run tamal:refresh nixpkgs # or just one
```

### How it fits together

| file | role |
| --- | --- |
| `nix/tamal/manifest.kdl` | hand-written. Inputs, and the `fresh-cmd` that decides what "latest" means for each. |
| `nix/tamal/lock.json` | machine-written. `nixtamal refresh` owns it. |
| `nix/tamal/default.nix` | machine-written **and regenerated on every lock** — it grows fetcher code to match the input kinds in use. Don't edit it. |
| `nix/compat.nix` | hand-written. Rebuilds the flake *outputs* (`nixosModules`, overlays, packages) that nixtamal doesn't know about. |
| `default.nix` | hand-written. Replaces Blueprint: rakes `modules/` into `flake.nixosModules.*` and supplies the `inputs` / `flake` / `perSystem` / `hostName` module arguments. |

Nothing under `hosts/` or `modules/` changed. That is deliberate — `nix/compat.nix`
and `default.nix` exist to reproduce Blueprint's module-argument contract exactly,
so the two build paths stay diffable.

### How close is it?

Both paths were evaluated against the *same* nixpkgs commit (`9fbb54b`) and the
resulting `nixosConfigurations.nutmeg` compared:

| | flake | nixtamal |
| --- | --- | --- |
| systemd services | 166 | 166 — no unit present on one side and missing on the other |
| `environment.systemPackages` | `ragenix-0.1.0` | `ragenix-2025.03.09` — the only difference |

The derivation hashes still differ, for two understood reasons: the ragenix
substitution above, and the `versionSuffix` difference described below. Nothing
else diverged.

### Things worth knowing

- **`default-fetch-time eval` is load-bearing.** Nixtamal defaults to fetching
  inputs at *build* time. Every input here gets `import`ed from, and importing
  out of a build-time-fetched input is import-from-derivation — which
  `nix-instantiate --eval` refuses outright. Flake inputs are always eval-time;
  `default-fetch-time eval` is what restores parity.
- **`slime-chat` is a private repo**, so it is a `git` input rather than an
  `archive` one (there is no unauthenticated codeload tarball). Evaluation
  works, because eval-time `git` compiles to `builtins.fetchGit` and inherits
  your git credentials. **Locking it does not**: `nixtamal lock` shells out to
  `nix-prefetch-git`, and that subprocess does not pick up the `gh auth
  git-credential` helper, so it fails with "could not read Username". Its lock
  entry is currently hand-written. This is the one unsolved problem here.
- **`nixos-version` changes.** Verified against the same nixpkgs commit, the
  flake reports `26.11.20260826.9fbb54b` and this reports
  `26.11pre1062397.9fbb54b33e91`. The second is the channel's own
  `.version-suffix`; the first is nixpkgs' `flake.nix` overriding it from lock
  metadata, which has no non-flake equivalent. Cosmetic, but it shows up in
  `nixos-version`, `/etc/os-release` and generation names.
- **Transitive inputs have to be hoisted by hand.** There is no `follows`. micasa
  needs `gitignore.nix` to build, so `gitignore` is an input of *this* repo now.
  Every input a build touches must be named in the manifest.
- **`nix/compat.nix` restates other people's flakes.** tsnsrv's package
  definition in particular is transcribed from its `perSystem`. Upstream can
  change how it builds and this will keep building the old way until something
  breaks. That is the standing maintenance cost of the conversion.

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
- [`docs/beszel-synology.md`](docs/beszel-synology.md) — the beszel agent on potato-bunny:
  hand-managed DSM container, why the hub address is an IP, and how to upgrade it.
