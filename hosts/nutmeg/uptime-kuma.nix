# Uptime Kuma — status board for the services, and the dead-man's-switch half
# of this host's monitoring (see modules/nixos/unit-heartbeat.nix).
#
# WHY A DEAD-MAN'S SWITCH AT ALL, given notify-failure already pushes to
# Telegram: OnFailure only fires when a unit *fails*. It would not have caught
# arr-backup-pin, which exited 0 for a day while every one of its four API
# calls failed, and it does not catch a timer that quietly stops firing at all.
# Both are "silence that looks like success", and only absence-detection finds
# them. The two layers are complementary, not redundant.
#
# KNOWN BLIND SPOT, stated plainly: this runs on nutmeg, so it cannot report
# nutmeg being down — and nutmeg is the host with a documented history of silent
# hard stops (see ./crash-diagnostics.nix). The Beszel hub has the same problem.
# That gap is covered from the outside by the watcher on pantry
# (modules/nixos/host-watch.nix), not from here.
{ config, ... }:
{
  services.uptime-kuma = {
    enable = true;
    settings = {
      # NOT the module default of 3001: aurral's container runs with
      # --network=host and already holds *:3001 on this box (see ./aurral.nix).
      # Same class of collision as beszel-vs-scanservjs on 8090 — don't "fix"
      # this back to the default.
      PORT = "3010";
      # Loopback only; reached over the tailnet through tsnsrv below. Nothing
      # here needs to be on the LAN, so no allowedTCPPorts entry.
      HOST = "127.0.0.1";
    };
  };

  # https://status.<tailnet>.ts.net -> 127.0.0.1:3010. The explicit v4 literal
  # rather than the "localhost" default, since HOST above binds v4 only and the
  # default would resolve to ::1 first (same fix as tautulli/aurral).
  services.tsnsrv.services.status.urlParts = {
    host = "127.0.0.1";
    port = 3010;
  };

  # Kuma's own state is worth keeping: it holds every monitor definition and
  # push token, which is precisely the hand-entered UI state that is annoying
  # to rebuild. Small (SQLite), so this is cheap.
  services.serviceBackup.jobs.uptime-kuma = {
    root = "/var/lib/uptime-kuma";
    sqlite = [ "kuma.db" ];
    optional = true; # the db only appears after first-run setup
  };

  services.notifyFailure.units = [ "uptime-kuma.service" ];

  # ── The heartbeats ────────────────────────────────────────────────────
  #
  # Each unit here gets a matching Push monitor, written straight into Kuma's
  # SQLite DB by uptime-kuma-monitor-sync on every deploy (see
  # modules/nixos/unit-heartbeat.nix for why the DB and not the web UI). The
  # push token is the unit name, so this list is the single source of truth and
  # there is nothing to copy back by hand.
  #
  # The one thing NOT automated is creating the admin account, which Kuma's
  # first-run wizard owns. Do that once in the browser, or with
  # `nix run .#provision-uptime-kuma`.
  #
  #
  # Deliberately NOT included:
  #   adf-autoscan       — Type=simple, Restart=always. It is a daemon, not a
  #                        job: "it succeeded" is not a thing it ever reports,
  #                        so a heartbeat would only ever mean "it started".
  #                        Its failures are covered by notify-failure instead.
  #   lidarr-beets-pin   — oneshot but boot-only (RemainAfterExit, no timer).
  #                        A heartbeat would go stale the first time uptime
  #                        exceeded the interval and then alert forever.
  # Admin credentials, used both for the web UI and by the provisioning script.
  # Kuma's first-run wizard creates this account; the script performs that setup
  # if it hasn't happened yet, so the account is reproducible rather than
  # something typed once and forgotten.
  age.secrets.uptime-kuma-admin.file = ../../secrets/uptime-kuma-admin.age;

  # Intervals must exceed the WORST-CASE gap between successful runs, which is
  # the timer's period plus its RandomizedDelaySec — not the period alone.
  # service-backup jitters by up to 1h on a daily timer, so 26h; restic by 30m,
  # so 25h. Sizing these at 24h would alert on perfectly healthy jobs.
  services.unitHeartbeat = {
    enable = true;
    baseUrl = "http://127.0.0.1:3010";
    units = [
      { unit = "restic-backups-nas.service"; interval = 90000; } # daily + 30m jitter
      { unit = "paperless-exporter.service"; interval = 90000; } # daily 01:30, no jitter
      { unit = "arr-backup-pin.service"; interval = 90000; } # daily + 20m jitter
      { unit = "recyclarr.service"; interval = 90000; } # daily
      { unit = "beets-sync.service"; interval = 21600; } # every 4h + 10m jitter
      { unit = "soularr.service"; interval = 7200; } # hourly + 5m jitter
      { unit = "avahi-name-check.service"; interval = 1800; } # every 5m
    ]
    ++ map (n: {
      unit = "service-backup-${n}.service";
      interval = 93600; # daily + up to 1h jitter
    }) (builtins.attrNames config.services.serviceBackup.jobs);
  };
}
