# Remote build cache for mbx (jdx's Rust build tool; packages/mbx-cache.nix).
#
# Clients restore compiled crates from here instead of rebuilding them, which is
# what lets them keep a small local mbx store (gc.max_size in their mbx config)
# on disk-constrained hosts: an evicted object costs a LAN download, not a
# recompile. pantry has the disk to hold everything.
#
#   https://pantry.vaquita-woodpecker.ts.net  (tailscale serve, below)
#     -> 127.0.0.1:8080 mbx-cache
#          blobs:    /var/lib/mbx-cache (filesystem storage)
#          metadata: local PostgreSQL over the unix socket
#
# Namespaces and tokens live in secrets/mbx-cache-tokens.age; see the note in
# secrets/secrets.nix. Nothing evicts blobs yet: the filesystem backend has no
# lifecycle rules, and a 4 TB disk makes that a later problem. When it isn't,
# delete old files under the data dir, then run
# `mbx-cache --sweep-metadata-older-than-days N` with N longer than the file
# age — a missing blob is only a cache miss, so a rough cut is safe.
{
  config,
  perSystem,
  ...
}: let
  listen = "127.0.0.1:8080";
in {
  age.secrets.mbx-cache-tokens.file = ../../secrets/mbx-cache-tokens.age;

  # The only database on this host, so the stock settings (128 MB shared
  # buffers) are left alone on a 3.9 GB box.
  services.postgresql = {
    enable = true;
    ensureDatabases = ["mbx-cache"];
    ensureUsers = [
      {
        name = "mbx-cache";
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.services.mbx-cache = {
    description = "mbx remote build cache";
    wantedBy = ["multi-user.target"];
    after = ["network.target" "postgresql.target"];
    requires = ["postgresql.target"];

    environment = {
      MBX_CACHE_LISTEN = listen;
      MBX_CACHE_STORAGE = "filesystem";
      MBX_CACHE_DATA_DIR = "/var/lib/mbx-cache";
      # Peer auth over the socket: the DynamicUser's name matches the role. The
      # user must be spelled out — with none, sqlx connects as "anonymous" rather
      # than the OS user. `localhost` is a placeholder; ?host= picks the socket.
      MBX_CACHE_DATABASE_URL = "postgres://mbx-cache@localhost/mbx-cache?host=/run/postgresql";
      # Plenty for two clients, and each connection is a postgres backend
      # process on a small box.
      MBX_CACHE_DATABASE_MAX_CONNECTIONS = "8";
      RUST_LOG = "info";
    };

    serviceConfig = {
      ExecStart = "${perSystem.self.mbx-cache}/bin/mbx-cache";
      # MBX_CACHE_TOKENS_JSON
      EnvironmentFile = config.age.secrets.mbx-cache-tokens.path;
      DynamicUser = true;
      User = "mbx-cache";
      StateDirectory = "mbx-cache";
      Restart = "on-failure";
      RestartSec = 5;

      CapabilityBoundingSet = "";
      NoNewPrivileges = true;
      ProtectHome = true;
      ProtectClock = true;
      ProtectKernelLogs = true;
      PrivateDevices = true;
      PrivateUsers = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      ProtectHostname = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
      ];
      UMask = "0077";
    };
  };

  # TLS in front of it. mbx refuses to send a bearer token over plain http to
  # anything but loopback, and mbx-cache doesn't terminate TLS itself.
  # `tailscale serve` uses this node's own ts.net certificate, so unlike tsnsrv
  # it needs no OAuth secret to mint a separate node. The serve config persists
  # in tailscaled's state; re-applying it is idempotent.
  systemd.services.mbx-cache-serve = {
    description = "Expose mbx-cache on the tailnet over HTTPS";
    wantedBy = ["multi-user.target"];
    after = ["tailscaled.service" "tailscaled-autoconnect.service"];
    wants = ["tailscaled.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # tailscaled may still be logging in at boot.
      Restart = "on-failure";
      RestartSec = 10;
      ExecStart = "${config.services.tailscale.package}/bin/tailscale serve --bg --https=443 http://${listen}";
      ExecStop = "${config.services.tailscale.package}/bin/tailscale serve --https=443 off";
    };
  };
}
