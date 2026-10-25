# mbx-cache: the Rust build cache for mbx (jdx's build tool; packages/mbx-cache.nix),
# with its metadata in a PostgreSQL of its own. Clients (nutmeg, the Mac) use
# modules/home/mbx-shared.nix.
#
#   https://potato-bunny.vaquita-woodpecker.ts.net:8443   (tailscale serve)
#     -> 127.0.0.1:8080 mbx-cache
#          blobs:    the `mbx-cache` share on volume2 (500 GB quota)
#          metadata: nix-postgresql, over its socket in /run/nix-postgresql
#
# 8443 because DSM's nginx owns 443, on the tailnet address too.
#
# This PostgreSQL is not DSM's (pgsql.service, 11.x, /run/postgresql, 5432,
# which DSM manages for its own databases): own account, data dir, socket dir
# and port, socket only.
#
# Secret, placed by hand (root, 0400):
#   /volume1/@appdata/nix-system/secrets/mbx-cache.env
#     MBX_CACHE_TOKENS_JSON='[...]' — the contents of secrets/mbx-cache-tokens.age
{
  pkgs,
  perSystem,
  ...
}: let
  pg = pkgs.postgresql_18;
  mbx = perSystem.self.mbx-cache;
  pgData = "/volume2/@appdata/postgresql";
  pgSocket = "/run/nix-postgresql";
  pgPort = "5433";
  psqlArgs = "-h ${pgSocket} -p ${pgPort}";
  blobs = "/volume2/mbx-cache";
  envFile = "/volume1/@appdata/nix-system/secrets/mbx-cache.env";
  gib = n: n * 1024 * 1024 * 1024;

  mbxEnv = ''
    Environment=MBX_CACHE_LISTEN=127.0.0.1:8080
    Environment=MBX_CACHE_STORAGE=filesystem
    Environment=MBX_CACHE_DATA_DIR=${blobs}
    Environment="MBX_CACHE_DATABASE_URL=postgres://svc-mbx-cache@localhost/mbx-cache?host=${pgSocket}&port=${pgPort}"
    Environment=MBX_CACHE_DATABASE_MAX_CONNECTIONS=8
    Environment=RUST_LOG=info
    EnvironmentFile=${envFile}
  '';

  # As root (PermissionsStartOnly): the data dir, and initdb exactly once.
  pgPreStart = pkgs.writeShellScript "nix-postgresql-pre-start" ''
    set -euo pipefail
    ${pkgs.coreutils}/bin/install -d -o svc-postgres -m 0700 ${pgData}
    if [ ! -e ${pgData}/PG_VERSION ]; then
      ${pkgs.util-linux}/bin/setpriv --reuid=svc-postgres --regid=users --init-groups -- \
        ${pg}/bin/initdb -D ${pgData} --auth=peer --encoding=UTF8 --no-locale
    fi
  '';

  # Once the socket answers, the role and database mbx-cache needs, if missing.
  pgPostStart = pkgs.writeShellScript "nix-postgresql-post-start" ''
    set -euo pipefail
    as_pg() { ${pkgs.util-linux}/bin/setpriv --reuid=svc-postgres --regid=users --init-groups -- "$@"; }
    for _ in $(${pkgs.coreutils}/bin/seq 60); do
      as_pg ${pg}/bin/pg_isready ${psqlArgs} -q && break
      ${pkgs.coreutils}/bin/sleep 0.5
    done
    q() { as_pg ${pg}/bin/psql -X ${psqlArgs} -d postgres -tAc "$1"; }
    [ "$(q "select 1 from pg_roles where rolname = 'svc-mbx-cache'")" = 1 ] ||
      as_pg ${pg}/bin/createuser ${psqlArgs} svc-mbx-cache
    [ "$(q "select 1 from pg_database where datname = 'mbx-cache'")" = 1 ] ||
      as_pg ${pg}/bin/createdb ${psqlArgs} -O svc-mbx-cache mbx-cache
  '';

  # Proxy tailnet :8443 to mbx-cache, unless that's already the serve config.
  # Never touches another port.
  serve = pkgs.writeShellScript "mbx-cache-serve" ''
    set -euo pipefail
    ts() { /var/packages/Tailscale/target/bin/tailscale --socket=/volume2/@appdata/Tailscale/tailscaled.sock "$@"; }
    if ts serve status --json | ${pkgs.jq}/bin/jq -e '
        [(.Web // {}) | to_entries[] | select(.key | endswith(":8443")) | .value.Handlers["/"].Proxy]
        | index("http://127.0.0.1:8080") != null' >/dev/null; then
      exit 0
    fi
    ts serve --bg --https=8443 http://127.0.0.1:8080
  '';
in {
  users.users.svc-postgres.description = "PostgreSQL for mbx-cache";
  users.users.svc-mbx-cache.description = "mbx-cache";

  dsm.shares.mbx-cache = {
    volume = "/volume2";
    description = "mbx-cache blobs (Nix-managed; mbx-cache.nix)";
    hidden = true;
    recycleBin = false;
    quotaMB = 500000;
    users.svc-mbx-cache = "rw";
  };

  systemd.units."nix-postgresql.service".text = ''
    [Unit]
    Description=PostgreSQL for mbx-cache (not DSM's)
    RequiresMountsFor=/volume2

    [Service]
    User=svc-postgres
    RuntimeDirectory=nix-postgresql
    PermissionsStartOnly=true
    ExecStartPre=${pgPreStart}
    ExecStart=${pg}/bin/postgres -D ${pgData} -c listen_addresses= -c unix_socket_directories=${pgSocket} -c port=${pgPort}
    ExecStartPost=${pgPostStart}
    KillSignal=SIGINT
    KillMode=mixed
    TimeoutSec=120
    Restart=on-failure
    RestartSec=5
  '';

  # Restart=on-failure also covers the first deploy, where the share and the
  # secret may appear after the unit's first start.
  systemd.units."mbx-cache.service".text = ''
    [Unit]
    Description=mbx remote build cache
    Requires=nix-postgresql.service
    After=nix-postgresql.service network-online.target
    RequiresMountsFor=/volume1 /volume2

    [Service]
    User=svc-mbx-cache
    ExecStart=${mbx}/bin/mbx-cache
    ${mbxEnv}
    NoNewPrivileges=yes
    PrivateTmp=yes
    ProtectSystem=full
    ProtectHome=yes
    CapabilityBoundingSet=
    Restart=on-failure
    RestartSec=5
  '';

  systemd.units."mbx-cache-serve.service".text = ''
    [Unit]
    Description=Publish mbx-cache on the tailnet (:8443)
    After=mbx-cache.service network-online.target

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=${serve}
  '';

  systemd.units."mbx-cache-evict.service" = {
    wantedBy = [];
    text = ''
      [Unit]
      Description=Keep mbx-cache's blobs under their cap
      After=mbx-cache.service

      [Service]
      Type=oneshot
      User=svc-mbx-cache
      Environment=PATH=${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.gawk}/bin
      Environment=DATA_DIR=${blobs}
      Environment=HIGH_BYTES=${toString (gib 450)}
      Environment=LOW_BYTES=${toString (gib 400)}
      Environment=MBX_CACHE=${mbx}/bin/mbx-cache
      ${mbxEnv}
      ExecStart=${pkgs.bash}/bin/bash ${./mbx-cache-evict.sh}
    '';
  };
  systemd.units."mbx-cache-evict.timer" = {
    wantedBy = ["timers.target"];
    text = ''
      [Unit]
      Description=Nightly mbx-cache size check

      [Timer]
      OnCalendar=*-*-* 03:30
      Persistent=true
    '';
  };
}
