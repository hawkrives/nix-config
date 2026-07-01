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
  systems = [
    nutmeg
    techcyte
    tuckles
    pantry
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

  # qui (alternate qBittorrent web UI) session secret (tuckles).
  "qui-session-secret.age".publicKeys = users ++ [ tuckles ];

  # Bare tailscale OAuth client secret (no ?ephemeral query) for tsnsrv's OAuth
  # key minting on tuckles. Same OAuth client as tailscale-authkey-tuckles.
  "tsnsrv-authkey-tuckles.age".publicKeys = users ++ [ tuckles ];
}
