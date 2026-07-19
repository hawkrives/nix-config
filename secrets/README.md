# Secrets (ragenix / agenix)

Secrets are age-encrypted files (`*.age`) committed to this repo. Each is encrypted
to a set of **recipient public keys** so that (a) the admins can edit/rekey it and
(b) the host(s) that consume it can decrypt it at activation with their SSH host key.

## Files

- **`secrets.nix`** — the rules file. Maps each `*.age` file to the public keys that
  may decrypt it (`users ++ [ <hosts> ]`). This is the source of truth for recipients.
- **`*.age`** — the encrypted secrets themselves.

## Add a new secret

```bash
cd ./secrets
# 1. Declare it in secrets.nix, choosing recipients:
#      "my-secret.age".publicKeys = users ++ [ nutmeg ];   # + whichever hosts consume it
# 2. Create/edit the encrypted content ($EDITOR opens on the decrypted plaintext):
ragenix -e my-secret.age
```

## Edit / rekey

```bash
cd ./secrets
ragenix -e my-secret.age          # edit contents
ragenix --rekey                   # re-encrypt everything after changing recipients in secrets.nix
```

## Consume a secret on a host

Reference it from the host config so agenix decrypts it at activation:

```nix
age.secrets.my-secret.file = ../../secrets/my-secret.age;
# → decrypts to /run/agenix/my-secret (default: root-owned, mode 0400)
# Set .owner / .group / .mode, or hand it to a service via
# systemd `EnvironmentFile=` / `LoadCredential=`.
```

> Flakes only see git-tracked files — `git add` a new `*.age` before `nixos-rebuild`,
> or the build won't find it.

## Content conventions in this repo

- **Env-file** secrets hold `KEY=value` lines (e.g. the `*-api-key.age` files hold
  `<APP>__AUTH__APIKEY=…`) and are injected via `environmentFiles` / `EnvironmentFile=`.
- **Bare** secrets hold the raw value only (no `KEY=` prefix, no trailing newline) —
  e.g. `hass-token.age` — for `Authorization: Bearer $(cat …)` or `LoadCredential=`.

See also [`docs/home-assistant.md`](../docs/home-assistant.md) for the `hass-token` secret
and why HA is driven through its API.
