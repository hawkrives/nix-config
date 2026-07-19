# Home Assistant (nutmeg)

Home Assistant runs as a Podman container on **nutmeg** (`hosts/nutmeg/home-assistant.nix`),
host-networked, systemd-managed as `podman-homeassistant.service`.

## Operate it through the API, not `.storage`

HA's UI-managed state lives in `/var/lib/home-assistant/.storage/` (dashboards,
`core.config_entries`, `core.entity_registry`, `core.device_registry`, …). **Do not
hand-edit those files.** They are a coupled store: a bad/empty write makes HA quarantine
the file on boot and rebuild from scratch, which then prunes every orphaned entity/device.
Direct edits also skip HA's validation and cascade logic (e.g. re-enabling a config entry
must cascade entry → device → entities).

Instead, drive HA through its **API**, which validates and writes atomically:

- **REST API** (`http://localhost:8123/api/`) — states, services, template, config check.
- **WebSocket API** (`ws://localhost:8123/api/websocket`) — everything the frontend does,
  including the things REST can't touch:
  - Dashboards: `lovelace/config`, `lovelace/config/save`, `lovelace/dashboards/*`
  - Frontend resources (HACS cards): `lovelace/resources`, `lovelace/resources/{create,update,delete}`
  - Config entries: `config_entries/get|update|disable`, `config_entries/flow/*`
  - Registries: `config/{entity,device,area}_registry/*`
- **`hass-cli`** wraps both and can send raw WS commands.

### Auth: the `hass-token` secret

A long-lived access token is stored as the ragenix secret **`hass-token`** (bare JWT),
deployed to `/run/agenix/hass-token`. See [`secrets/README.md`](../secrets/README.md).

```bash
TOKEN=$(sudo cat /run/agenix/hass-token)
curl -sS -H "Authorization: Bearer $TOKEN" http://localhost:8123/api/            # {"message":"API running."}
curl -sS -H "Authorization: Bearer $TOKEN" http://localhost:8123/api/config | jq .version
```

## Gotchas

- **Manage the container with systemd, not podman.** The unit uses `--rm`, so
  `podman stop homeassistant` *deletes* the container. Use
  `sudo systemctl restart podman-homeassistant.service`.
- **The container can't resolve `.local`** (no mDNS inside it). Integration URLs must use
  LAN IPs (e.g. qBittorrent/SABnzbd on tuckles `192.168.1.66`), not `tuckles.local`.
- **Full backups** are written nightly to `/var/lib/home-assistant/backups/*.tar` — the
  fallback if `.storage` is ever damaged.

## Deploying config changes

This repo uses **`nh`**, not `nixos-rebuild` directly:

```bash
nh os switch      # build + activate the current host's flake config
nh os boot        # activate on next boot only
```
