# ragenix rules file: maps each secret to the public keys that may decrypt it.
# Edit secrets from inside this directory:  cd secrets && ragenix -e <name>.age
# After changing recipients:                ragenix --rekey
let
  # user keys (for editing/rekeying secrets)
  natsume = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5cvA90dd+syRxeLBrQEdwBGmM4kC4pZBcbnya1g5sw";
  hawken-rives = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILFhbHFf1LJ/NseB3yDEAKNu3CGNDs+ot8qdQA5LI4rU";
  users = [
    natsume
    hawken-rives
  ];

  # host keys (each host decrypts its own secrets at activation via
  # /etc/ssh/ssh_host_ed25519_key)
  nutmeg = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINRtF1Gu1NN25zb3ZWL+D2XBn2i0FszefxLVMwhItgOb";
  techcyte = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZW19gGFVWa3uCxOv4CHItnUuucmNQiExpgMAqTUSNO";
  tuckles = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKaiGtVceXg9xJh0+jIIhFKZtnlNdPaWCZqSp0KNsb6r";
  pantry = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBiUQ0Plm2ceonVERAP0m5NoEH39J3jCsuxQgOxW1K67";
  bigpond = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICwYnYwie4qge41DnWPPn+sL3n/97y8883FanBwhkSTj";
  systems = [
    nutmeg
    techcyte
    tuckles
    pantry
    bigpond
  ];
in
{
  # Example secret proving the workflow end-to-end. Wired on nutmeg only.
  "example.age".publicKeys = users ++ [ nutmeg ];

  # paperless superuser password (nutmeg).
  "paperless-admin-pass.age".publicKeys = users ++ [ nutmeg ];

  # peertube signing secret (nutmeg).
  "peertube-secret.age".publicKeys = users ++ [ nutmeg ];

  # lidarr API key, injected via environmentFiles (nutmeg).
  "lidarr-api-key.age".publicKeys = users ++ [ nutmeg ];

  # radarr API key, injected via environmentFiles (nutmeg).
  "radarr-api-key.age".publicKeys = users ++ [ nutmeg ];

  # sonarr API key, injected via environmentFiles (nutmeg).
  "sonarr-api-key.age".publicKeys = users ++ [ nutmeg ];

  # prowlarr API key, injected via environmentFiles (nutmeg).
  "prowlarr-api-key.age".publicKeys = users ++ [ nutmeg ];

  # Bare radarr/sonarr API keys (value only, no KEY= prefix) for recyclarr, whose
  # `_secret` LoadCredential substitution wants the raw key. Same keys as the
  # *-api-key.age env-files above, just unwrapped (nutmeg).
  "radarr-api-key-bare.age".publicKeys = users ++ [ nutmeg ];
  "sonarr-api-key-bare.age".publicKeys = users ++ [ nutmeg ];

  # Soulseek account credentials for slskd (tuckles only).
  "slskd-env.age".publicKeys = users ++ [ tuckles ];

  # slskd web API key — shared by slskd (tuckles) and Soularr (nutmeg).
  "slskd-api-key.age".publicKeys = users ++ [ nutmeg tuckles ];

  # Mullvad WireGuard config (full wg-quick file) for the VPN namespace (tuckles).
  "wg-mullvad-tuckles.age".publicKeys = users ++ [ tuckles ];

  # Tailscale auth key for tuckles.
  "tailscale-authkey-tuckles.age".publicKeys = users ++ [ tuckles ];

  # Tailscale auth key for pantry (cache VM).
  "tailscale-authkey-pantry.age".publicKeys = users ++ [ pantry ];

  # Tailscale auth key for bigpond (T2 MacBook builder).
  "tailscale-authkey-bigpond.age".publicKeys = users ++ [ bigpond ];

  # qui (alternate qBittorrent web UI) session secret (tuckles).
  "qui-session-secret.age".publicKeys = users ++ [ tuckles ];

  # Bare tailscale OAuth client secret (no ?ephemeral query) for tsnsrv's OAuth
  # key minting on tuckles. Same OAuth client as tailscale-authkey-tuckles.
  "tsnsrv-authkey-tuckles.age".publicKeys = users ++ [ tuckles ];

  # Same, for nutmeg. It grants the ability to mint tailnet nodes, so it lives
  # here rather than as a file on the host, where it would be readable by every
  # local user — `techcyte` has ssh access to nutmeg.
  "tsnsrv-authkey-nutmeg.age".publicKeys = users ++ [ nutmeg ];

  # slime-chat Twitch OAuth app credentials (TWITCH_CLIENT_ID / _SECRET),
  # injected via environmentFile (nutmeg).
  "slime-chat-env.age".publicKeys = users ++ [ nutmeg ];

  # Home Assistant long-lived access token (raw JWT, no trailing newline) for
  # driving the HA REST/WebSocket API instead of hand-editing .storage (nutmeg).
  "hass-token.age".publicKeys = users ++ [ nutmeg ];

  # Plex API token for channel-archive's post-download restructure step
  # (nutmeg).
  "plex-token.age".publicKeys = users ++ [ nutmeg ];

  # Beszel universal registration token (env-file: TOKEN=…). Every agent uses
  # the same token to self-register with the hub on nutmeg, so every host that
  # runs an agent is a recipient.
  "beszel-token.age".publicKeys = users ++ [
    nutmeg
    tuckles
    pantry
    bigpond
  ];

  # restic repository password (nutmeg). ONE password for both the NAS and the
  # rsync.net repo: the two hold identical data and the same host writes both,
  # so splitting them buys nothing. Losing this file means the backups are
  # unrecoverable — it belongs in a password manager as well as here. Read it
  # back with: cd secrets && EDITOR=cat ragenix -e restic-password-nutmeg.age
  "restic-password-nutmeg.age".publicKeys = users ++ [ nutmeg ];

  # SSH private key restic uses to reach both SFTP destinations (the Synology
  # and rsync.net). Deliberately NOT reusing /etc/ssh/ssh_host_ed25519_key the
  # way cache-push does: that key is nutmeg's identity to the rest of the
  # fleet, and handing a copy of its authority to a third-party provider's
  # authorized_keys is a wider blast radius than a purpose-made key.
  "restic-ssh-key-nutmeg.age".publicKeys = users ++ [ nutmeg ];

  # Uptime Kuma admin account (env file: UPTIME_KUMA_USER / _PASSWORD). Logs
  # into the web UI, and lets packages/provision-uptime-kuma.nix drive Kuma's
  # first-run wizard, which is the only part of its setup that is not
  # declarative.
  "uptime-kuma-admin.age".publicKeys = users ++ [ nutmeg ];

  # Telegram bot credentials for systemd failure notifications (env file with
  # TELEGRAM_BOT_TOKEN= and TELEGRAM_CHAT_ID=). Every host that runs the
  # notify-failure module needs it.
  "telegram-notify.age".publicKeys = users ++ [
    nutmeg
    tuckles
    pantry
  ];

  # Binary-cache signing keys, one per host, named for networking.hostName so
  # host-shared.nix can pick its own by interpolation. Each is readable only by
  # the host it belongs to — a signing key is that host's identity to the rest
  # of the fleet, and nothing is gained by sharing it sideways.
  #
  # Regenerate one with:
  #   nix key generate-secret --key-name <host> > key
  #   nix key convert-secret-to-public < key   # -> extra-trusted-public-keys
  #   cd secrets && EDITOR='cp ../key' ragenix -e nix-signing-key-<host>.age
  # Names are unique in nix's trusted-key map, so re-keying a host revokes
  # everything it signed before rather than adding to it.
  "nix-signing-key-nutmeg.age".publicKeys = users ++ [ nutmeg ];
  "nix-signing-key-tuckles.age".publicKeys = users ++ [ tuckles ];
  "nix-signing-key-pantry.age".publicKeys = users ++ [ pantry ];
  "nix-signing-key-Techcyte-DGQJV434PF.age".publicKeys = users ++ [ techcyte ];
}
