# paperless-ngx: the document archive, next to the rest of the NAS's data.
#
#   https://paperless.vaquita-woodpecker.ts.net   (tsnsrv.nix)
#     -> 127.0.0.1:28981 paperless-web
#   data, media, search index:  /volume2/@appdata/paperless
#   metadata:                   PostgreSQL (nix-postgresql, mbx-cache.nix), db
#                               `paperless`, role svc-paperless (peer auth)
#   task broker:                nix-redis-paperless, socket only
#   intake:                     /volume2/@appdata/paperless/consume
#   nightly export:             /volume1/app-servarr/paperless/export
#
# The scanner tools (scanner.nix) drop scans into the consume folder.
# restic (restic.nix) backs the export up, onsite and offsite: the export, not
# the data dir, because the metadata lives in PostgreSQL and only the export
# carries both. It sits on volume1, apart from the data on volume2.
#
# The units are the NixOS module's four (web, consumer, scheduler, task queue)
# as systemd-219 units. Their environment comes from evaluating that module
# with these settings, so it stays what the module would give them.
#
# The admin account lives in the database. To reset its password:
#   sudo setpriv --reuid=svc-paperless --regid=users --init-groups -- paperless-manage changepassword admin
{
  lib,
  pkgs,
  flake,
  ...
}: let
  data = "/volume2/@appdata/paperless";
  consume = "${data}/consume";
  share = "/volume1/app-servarr/paperless";
  export = "${share}/export";
  redisSock = "/run/nix-redis-paperless/redis.sock";
  port = 28981;

  # test_ignores_event_for_already_queued_file gives the file watcher only 2s
  # to queue a copied file; on a loaded builder it misses that window and the
  # build fails. Same shape as the watcher test nixpkgs already skips as flaky.
  package = pkgs.paperless-ngx.overrideAttrs (old: {
    disabledTests = (old.disabledTests or []) ++ ["test_ignores_event_for_already_queued_file"];
  });

  settings = {
    PAPERLESS_DBENGINE = "postgresql";
    PAPERLESS_DBHOST = "/run/nix-postgresql";
    PAPERLESS_DBPORT = "5433";
    PAPERLESS_DBNAME = "paperless";
    PAPERLESS_DBUSER = "svc-paperless";
    PAPERLESS_REDIS = "unix://${redisSock}";

    PAPERLESS_CONSUMER_IGNORE_PATTERN = [
      ".DS_STORE/*"
      "desktop.ini"
    ];
    # Trims tesseract's trained data to these languages (+ eng/osd/equ, always
    # included) instead of all ~130 (~1 GB).
    PAPERLESS_OCR_LANGUAGE = "eng+jpn";
    # Scans arrive as 300dpi colour JPEGs; lossless storage of those makes very
    # large archive files, so re-encode as JPEG inside the PDF/A.
    PAPERLESS_OCR_USER_ARGS = {
      optimize = 1;
      pdfa_image_compression = "jpeg";
    };
    # Feeder scans can arrive rotated; orient them from detected text.
    PAPERLESS_OCR_ROTATE_PAGES = true;
  };

  nixos = flake.inputs.nixpkgs.lib.nixosSystem {
    inherit (pkgs.stdenv.hostPlatform) system;
    modules = [
      {
        services.paperless = {
          enable = true;
          inherit package settings;
          dataDir = data;
          consumptionDir = consume;
          address = "127.0.0.1";
          inherit port;
          domain = "paperless.vaquita-woodpecker.ts.net";
          # Tika + gotenberg convert office documents, dragging in LibreOffice
          # and Chromium; only PDFs and scans come here.
          configureTika = false;
        };
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
        system.stateVersion = "25.11";
      }
    ];
  };
  envOf = unit: removeAttrs nixos.config.systemd.services.${unit}.environment ["PATH"];

  # Runs its arguments with the module's environment for `unit`, plus the
  # secret key (generated once, as the module does) and the module's PATH.
  withEnv = unit:
    pkgs.writeShellScript "paperless-env-${unit}" ''
      ${lib.concatStrings (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}\n") (envOf unit))}
      export PATH=${lib.escapeShellArg nixos.config.systemd.services.${unit}.environment.PATH}:$PATH
      set -a
      . ${data}/nixos-paperless-secret-key.env
      set +a
      exec "$@"
    '';

  paperless-manage = pkgs.writeShellScriptBin "paperless-manage" ''
    exec ${withEnv "paperless-scheduler"} ${package}/bin/paperless-ngx "$@"
  '';

  asPaperless = "${pkgs.util-linux}/bin/setpriv --reuid=svc-paperless --regid=users --init-groups --";

  # As root: directories, ownership, the database, and the secret key.
  preStartRoot = pkgs.writeShellScript "paperless-pre-start-root" ''
    set -euo pipefail
    PATH=${lib.makeBinPath [pkgs.coreutils pkgs.util-linux]}
    install -d -o svc-paperless -m 0750 ${data}
    chown -R svc-paperless ${data}
    install -d -o svc-paperless -m 0750 ${consume}
    install -d -m 0755 ${share}
    install -d -o svc-paperless -m 0755 ${export}

    if [ ! -s ${data}/nixos-paperless-secret-key.env ]; then
      key=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 64)
      (umask 077; echo "PAPERLESS_SECRET_KEY=$key" > ${data}/nixos-paperless-secret-key.env)
      chown svc-paperless ${data}/nixos-paperless-secret-key.env
    fi

    q() { setpriv --reuid=svc-postgres --regid=users --init-groups -- ${pkgs.postgresql_18}/bin/psql -X -h /run/nix-postgresql -p 5433 -d postgres -tAc "$1"; }
    [ "$(q "select 1 from pg_roles where rolname = 'svc-paperless'")" = 1 ] ||
      q 'create role "svc-paperless" login'
    [ "$(q "select 1 from pg_database where datname = 'paperless'")" = 1 ] ||
      q 'create database paperless owner "svc-paperless"'
  '';

  # As the service account: the module's migrate and search-index steps.
  preStart = pkgs.writeShellScript "paperless-pre-start" ''
    set -euo pipefail
    versionFile=${data}/src-version
    if [ "$(cat $versionFile 2>/dev/null || echo 0)" != ${package.version} ]; then
      ${package}/bin/paperless-ngx migrate
      echo ${package.version} > $versionFile
    fi
    ${package}/bin/paperless-ngx document_index reindex --if-needed --no-progress-bar
  '';

  unit = name: {
    description,
    exec,
    extra ? "",
  }: ''
    [Unit]
    Description=${description}
    ConditionPathIsMountPoint=/volume2
    OnFailure=notify-failure@%n.service
    Requires=nix-postgresql.service nix-redis-paperless.service
    After=nix-postgresql.service nix-redis-paperless.service network-online.target
    RequiresMountsFor=/volume1 /volume2
    ${extra}
    [Service]
    User=svc-paperless
    ExecStart=${withEnv name} ${exec}
    Restart=on-failure
    RestartSec=10
  '';
in {
  users.users.svc-paperless.description = "paperless-ngx";

  profileExtra = [paperless-manage];

  tsnsrv.services.paperless.upstream = "http://127.0.0.1:${toString port}";

  uptimeKuma.localHeartbeats = [
    {
      unit = "paperless-exporter.service";
      interval = 90000; # daily 01:30, no jitter
    }
  ];

  systemd.units."nix-redis-paperless.service".text = ''
    [Unit]
    Description=Redis for paperless (task broker)
    OnFailure=notify-failure@%n.service

    [Service]
    User=svc-paperless
    RuntimeDirectory=nix-redis-paperless
    ExecStart=${pkgs.redis}/bin/redis-server --port 0 --unixsocket ${redisSock} --unixsocketperm 600 --save "" --appendonly no
    Restart=on-failure
    RestartSec=5
  '';

  # Migrations run here; the other three wait for it.
  systemd.units."paperless-scheduler.service".text = unit "paperless-scheduler" {
    description = "paperless: scheduler (celery beat)";
    exec = "${package}/bin/celery --app paperless beat --loglevel INFO";
    extra = ''
      [Service]
      PermissionsStartOnly=true
      ExecStartPre=${preStartRoot}
      ExecStartPre=${asPaperless} ${withEnv "paperless-scheduler"} ${preStart}
    '';
  };

  systemd.units."paperless-task-queue.service".text = unit "paperless-task-queue" {
    description = "paperless: task queue (celery worker)";
    exec = "${package}/bin/celery --app paperless worker --loglevel INFO";
    extra = ''
      Wants=paperless-scheduler.service
      After=paperless-scheduler.service
    '';
  };

  systemd.units."paperless-consumer.service".text = unit "paperless-consumer" {
    description = "paperless: consumer";
    exec = "${package}/bin/paperless-ngx document_consumer";
    extra = ''
      Wants=paperless-scheduler.service
      After=paperless-scheduler.service
    '';
  };

  systemd.units."paperless-web.service".text = unit "paperless-web" {
    description = "paperless: web server";
    exec = "${nixos.config.services.paperless.package.python.pkgs.granian}/bin/granian --interface asginl --ws paperless.asgi:application";
    extra = ''
      Wants=paperless-scheduler.service
      After=paperless-scheduler.service
    '';
  };

  systemd.units."paperless-exporter.service" = {
    wantedBy = [];
    text = ''
      [Unit]
      Description=paperless: nightly export to ${export}
      ConditionPathIsMountPoint=/volume2
      OnFailure=notify-failure@%n.service
      Requires=nix-postgresql.service
      After=nix-postgresql.service paperless-scheduler.service
      RequiresMountsFor=/volume1 /volume2

      [Service]
      Type=oneshot
      User=svc-paperless
      ExecStart=${withEnv "paperless-scheduler"} ${package}/bin/paperless-ngx document_exporter ${export} --compare-checksums --delete --no-color --no-progress-bar
      # Documents keep their 0600 from the data dir; restic reads the export
      # as hawken, through the users group.
      ExecStartPost=${pkgs.coreutils}/bin/chmod -R g+rX ${export}
      # The heartbeat: Uptime Kuma alerts if this stops arriving (uptime-kuma.nix).
      ExecStartPost=${pkgs.curl}/bin/curl -fsS --max-time 20 -o /dev/null "http://127.0.0.1:3010/api/push/paperless-exporter?status=up&msg=OK"
    '';
  };
  systemd.units."paperless-exporter.timer" = {
    wantedBy = ["timers.target"];
    text = ''
      [Unit]
      Description=paperless: nightly export

      [Timer]
      OnCalendar=*-*-* 01:30
      Persistent=true
    '';
  };
}
