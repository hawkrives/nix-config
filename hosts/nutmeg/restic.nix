# Encrypted, deduplicated, versioned backups of the small irreplaceable set —
# to the NAS *and* off site.
#
# This is COMPLEMENTARY to modules/nixos/service-backup.nix, not a replacement.
# service-backup gives a browsable plaintext mirror on the NAS: you can cd into
# it and grab a config.xml. restic gives history, dedup and encryption, at the
# cost of needing the password and the restic binary to read anything. Keep both.
#
# Scope is deliberately narrow. Media is not here: it is large, re-acquirable,
# and already on the NAS. What is here is the stuff that no amount of money or
# time gets back — scanned documents, and Home Assistant's registries.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # FLIP THIS TO true ONCE THE PUBLIC KEY IS INSTALLED ON rsync.net.
  #
  # Everything about the offsite job is configured and correct, but the account
  # has not yet been told to trust this host's key, so the job cannot succeed:
  #   de3044@de3044.rsync.net: Permission denied (publickey,password,…)
  # Leaving the timer live in that state would mean a failed unit and a Telegram
  # alert every single night, which is how you teach yourself to ignore alerts.
  # So it stays declaratively off, and the fact that it's off is visible in git
  # rather than hidden in a broken timer.
  #
  # To enable — needs the rsync.net account password once:
  #   ssh de3044@de3044.rsync.net 'mkdir -p .ssh restic/nutmeg && cat >> .ssh/authorized_keys' \
  #     <<< 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAe3hWozQOUE7TrNLUAyG8YwcSAjEfUm5id069iC5YMR restic@nutmeg'
  # then set this true, redeploy, and check with:
  #   sudo systemctl start restic-backups-offsite.service
  #
  # The endpoint here (de3044@de3044.rsync.net) supersedes the 57198@usw-s007
  # account that the Synology's Hyper Backup still targets — rsync.net appears
  # to have moved the account. Both resolve and accept connections; only this
  # one is current. Verified 2026-08-29 that this host's key is not yet in its
  # authorized_keys ("Permission denied (publickey,…)"), which is the only
  # thing standing between here and a working offsite backup.
  enableOffsite = false;

  sshKey = config.age.secrets.restic-ssh-key-nutmeg.path;
  password = config.age.secrets.restic-password-nutmeg.path;

  # Shared by both repos. See the note in secrets/secrets.nix on why one key.
  paths = [
    # Paperless: the EXPORT, not /var/lib/paperless.
    #
    # This host runs paperless against PostgreSQL (PAPERLESS_DBENGINE=postgresql,
    # database.createLocally = true), so the document *metadata* — tags,
    # correspondents, dates, the lot — lives in postgres, not under the data dir.
    # Backing up /var/lib/paperless would have produced a pile of PDFs with no
    # index and looked like a working backup. (The stale db.sqlite3 sitting in
    # there is a leftover from before the postgres migration; it is not live.)
    #
    # document_exporter writes a self-contained, restorable tree: originals plus
    # a manifest carrying everything from the DB. It also stops the paperless
    # services while it runs, so the export is consistent rather than a hot copy.
    config.services.paperless.exporter.directory

    # Home Assistant, minus the two things that dominate its size (see excludes).
    config.users.users.homeassistant.home
  ];

  excludes = [
    # 2.9G of daily ~210MB tarballs whose contents are internally gzipped, so
    # restic dedups them badly — each run would add most of a full copy. They
    # already go to the NAS nightly via the service-backup home-assistant job.
    "${config.users.users.homeassistant.home}/backups"
    "${config.users.users.homeassistant.home}/tmp_backups"

    # The recorder database: 790MB of sensor history that churns constantly, so
    # it too dedups badly. THIS IS A REAL TRADEOFF, not an oversight: what
    # survives off site is your *configuration* (.storage — registries, config
    # entries, dashboards, auth — plus custom_components, themes, blueprints,
    # www), not your history. Rebuilding those by hand is days of work;
    # historical sensor graphs are a nice-to-have that the NAS copy still holds.
    # If you want history off site too, the right fix is a periodic
    # `sqlite3 .backup` of it (a hot file copy of a live SQLite DB is not a
    # backup) rather than deleting these two lines.
    "${config.users.users.homeassistant.home}/home-assistant_v2.db"
    "${config.users.users.homeassistant.home}/home-assistant_v2.db-wal"
    "${config.users.users.homeassistant.home}/home-assistant_v2.db-shm"

    "${config.users.users.homeassistant.home}/.cache"
    "${config.users.users.homeassistant.home}/*.log"
    "${config.users.users.homeassistant.home}/*.log.*"
  ];

  # Keep a long tail cheaply — restic dedups, so old snapshots of a mostly
  # static tree cost almost nothing. The failure this is sized for is "I didn't
  # notice the corruption for six months", which a 7-day window would not catch.
  pruneOpts = [
    "--keep-daily 14"
    "--keep-weekly 8"
    "--keep-monthly 24"
    "--keep-yearly 3"
  ];

  common = {
    inherit paths pruneOpts;
    exclude = excludes;
    passwordFile = password;
    initialize = true;
  };
in
{
  age.secrets.restic-ssh-key-nutmeg.file = ../../secrets/restic-ssh-key-nutmeg.age;
  age.secrets.restic-password-nutmeg.file = ../../secrets/restic-password-nutmeg.age;

  # Turn on paperless's own exporter so there is something correct to back up.
  # Runs at 01:30; both restic jobs run after it (see timerConfig below), so a
  # snapshot always contains that morning's export rather than yesterday's.
  #
  # `delete = true` + `compare-checksums = true` make the export an incremental
  # mirror rather than an ever-growing pile. Cost is ~55MB (media is only 54MB
  # here); the 96MB classification_model.pickle in the data dir is regenerable
  # and the exporter does not include it.
  services.paperless.exporter = {
    enable = true;
    onCalendar = "01:30:00";
  };

  # Host aliases rather than stuffing an `ssh -i …` invocation into restic's
  # `-o sftp.command`, which would have to survive both Nix string escaping and
  # systemd's ExecStart quoting. This way the repository URL stays trivial.
  #
  # Host keys are pinned inline for the same reason cache-push.nix pins
  # pantry's: restic runs non-interactively as root, and a root known_hosts
  # that has to be seeded by hand is exactly the kind of imperative state this
  # repo keeps trying to get rid of.
  programs.ssh.knownHosts = {
    "192.168.1.194".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILs4U5pSxhPtHJbYtqf306kgXYAYjri8CI+O9YtR1xzV";
    "de3044.rsync.net".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIObQN4P/deJ/k4P4kXh6a9K4Q89qdyywYetp9h3nwfPo";
  };

  programs.ssh.extraConfig = ''
    Host restic-nas
      HostName 192.168.1.194
      User hawken
      IdentityFile ${sshKey}
      IdentitiesOnly yes

    Host restic-offsite
      HostName de3044.rsync.net
      User de3044
      IdentityFile ${sshKey}
      IdentitiesOnly yes
  '';

  services.restic.backups = {
    # ── NAS ────────────────────────────────────────────────────────────
    # SFTP rather than a path under /mnt deliberately. The NFS shares here are
    # x-systemd.automount with a 5m idle-timeout, and restic holds lock files
    # for the length of a run; a mount that idle-unmounts under an active repo
    # is how you get stale locks that need a manual `restic unlock`. SFTP has
    # no such interaction.
    #
    # NOTE THE PATH. DSM chroots its SFTP subsystem to the share list, so over
    # SFTP the shares appear at the root: this is /app-backup/…, NOT
    # /volume1/app-backup/… the way it looks over an interactive ssh or NFS.
    # Getting that wrong fails confusingly — restic reports "permission denied"
    # creating the repo rather than "no such path" — and `ssh restic-nas ls
    # /volume1/app-backup` succeeding is a red herring, because that is the
    # shell, not the sftp subsystem. Check with:
    #   printf 'ls /\n' | sftp -b - restic-nas
    nas = common // {
      repository = "sftp:restic-nas:/app-backup/restic/nutmeg";
      timerConfig = {
        OnCalendar = "03:00";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
      # Cheap over the LAN, so verify structure every run.
      runCheck = true;
    };

    # ── Off site (rsync.net) ───────────────────────────────────────────
    # Same account the Synology's Hyper Backup already uses, in its own
    # subdirectory so the two cannot collide.
    offsite = lib.mkIf enableOffsite (common // {
      repository = "sftp:restic-offsite:restic/nutmeg";
      timerConfig = {
        OnCalendar = "04:00";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
      # NOT enabled here: `restic check` over SFTP to a remote provider is
      # latency-bound on a great many small round trips and would run for
      # hours. rsync.net ships restic server-side, so the cheap way to verify
      # this repo is to run it *there* over ssh:
      #   ssh restic-offsite restic -r restic/nutmeg check --read-data-subset=5%
      # Worth doing periodically by hand until that is scripted.
      runCheck = false;
    });
  };

  # Both restic jobs and the exporter they depend on. A silent backup failure is
  # the worst kind, since you find out when you need the backup.
  services.notifyFailure.units = [
    "restic-backups-nas.service"
    "paperless-exporter.service"
  ]
  # Only watch the offsite unit when it actually exists; naming a non-existent
  # unit here would quietly define an empty stub (see notify-failure.nix).
  ++ lib.optional enableOffsite "restic-backups-offsite.service";

  # `restic-nas` / `restic-offsite` wrappers land in PATH (createWrapper
  # defaults true), pre-set with the repo and password, for restores:
  #   restic-nas snapshots
  #   restic-nas restore latest --target /tmp/restore
  environment.systemPackages = [ pkgs.restic ];

  # Paperless's exporter stops the paperless services while it runs, and the
  # restic jobs must not start until the export they read has finished.
  systemd.services.restic-backups-nas.after = [ "paperless-exporter.service" ];

  systemd.services.restic-backups-offsite = lib.mkIf enableOffsite {
    after = [ "paperless-exporter.service" ];
    # Pushes over the WAN; keep it from starving interactive use.
    serviceConfig = {
      IOSchedulingClass = "idle";
      Nice = 10;
    };
  };

  # Assert the exporter directory is actually inside what we back up, so a
  # future change to either can't silently decouple them.
  assertions = [
    {
      assertion = lib.elem config.services.paperless.exporter.directory paths;
      message = "restic.nix: paperless export dir is not in the restic paths";
    }
  ];
}
