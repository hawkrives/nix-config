# This host's dead-man's-switch heartbeats (modules/nixos/unit-heartbeat.nix):
# each unit below pings Uptime Kuma on potato-bunny when it succeeds, and Kuma
# alerts when a ping is overdue. Kuma itself, and the Push monitors these
# units ping, live in hosts/potato-bunny/uptime-kuma.nix.
#
# WHY A DEAD-MAN'S SWITCH AT ALL, given notify-failure already pushes to
# Telegram: OnFailure only fires when a unit *fails*. It would not have caught
# arr-backup-pin, which exited 0 for a day while every one of its four API
# calls failed, and it does not catch a timer that quietly stops firing at all.
# Both are "silence that looks like success", and only absence-detection finds
# them. The two layers are complementary, not redundant.
{config, ...}: {
  # Deliberately NOT included:
  #   adf-autoscan       — Type=simple, Restart=always. It is a daemon, not a
  #                        job: "it succeeded" is not a thing it ever reports,
  #                        so a heartbeat would only ever mean "it started".
  #                        Its failures are covered by notify-failure instead.
  #   lidarr-beets-pin   — oneshot but boot-only (RemainAfterExit, no timer).
  #                        A heartbeat would go stale the first time uptime
  #                        exceeded the interval and then alert forever.

  # Kuma's admin credentials, used for the web UI and by
  # `KUMA_URL=http://[<potato-bunny ULA>]:3010 sudo nix run .#provision-uptime-kuma`,
  # which creates the account on a fresh Kuma, so it is reproducible rather
  # than something typed once and forgotten.
  age.secrets.uptime-kuma-admin.file = ../../secrets/uptime-kuma-admin.age;

  # Intervals must exceed the WORST-CASE gap between successful runs, which is
  # the timer's period plus its RandomizedDelaySec — not the period alone.
  # service-backup jitters by up to 1h on a daily timer, so 26h; restic by 30m,
  # so 25h. Sizing these at 24h would alert on perfectly healthy jobs.
  services.unitHeartbeat = {
    enable = true;
    # potato-bunny's tailnet ULA: this host can't resolve MagicDNS names.
    baseUrl = "http://[fd7a:115c:a1e0:ab12:4843:cd96:626f:fb9c]:3010";
    units =
      [
        {
          unit = "restic-backups-nas.service";
          interval = 90000;
        } # daily + 30m jitter
        {
          unit = "arr-backup-pin.service";
          interval = 90000;
        } # daily + 20m jitter
        {
          unit = "recyclarr.service";
          interval = 90000;
        } # daily
        {
          unit = "beets-sync.service";
          interval = 21600;
        } # every 4h + 10m jitter
        {
          unit = "avahi-name-check.service";
          interval = 1800;
        } # every 5m
      ]
      ++ map (n: {
        unit = "service-backup-${n}.service";
        interval = 93600; # daily + up to 1h jitter
      }) (builtins.attrNames config.services.serviceBackup.jobs);
  };
}
