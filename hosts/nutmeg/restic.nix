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
  utils,
  synologyMount,
  ...
}:
let
  # The NAS share the service-backup mirror lives on, as a systemd unit name.
  # Derived rather than hand-spelled "mnt-servarr.mount", so it stays correct
  # if the mountpoint ever moves.
  servarrMount = "${utils.escapeSystemdPath "/mnt/servarr"}.mount";
  syncthingMount = "${utils.escapeSystemdPath "/mnt/syncthing"}.mount";

  # A flag rather than a hardcoded true because the offsite job depends on
  # state outside this repo: this host's key being in the rsync.net account's
  # authorized_keys. If that goes away, set this false in a commit rather than
  # leaving a timer that fails into Telegram nightly, which is how you teach
  # yourself to ignore alerts.
  #
  # Two things to know about this endpoint:
  #
  #   * The account is de3044@de3044.rsync.net. `id` there reports
  #     uid=57198(de3044), so the 57198 references in the Synology's synovfs
  #     config point at this same account under an older name, not a second one.
  #   * rsync.net gives you a RESTRICTED shell. It has no output redirection, so
  #     the usual `cat >> .ssh/authorized_keys` idiom fails with "Error parsing
  #     command: Output redirection not supported" — which looks like an auth
  #     problem and is not. Manage that file by scp'ing it down, editing it
  #     locally and scp'ing it back, and append rather than overwrite: the
  #     account holds an unrelated key besides this host's.
  enableOffsite = true;

  # The Syncthing tree on the NAS, ~50GB across 10 folders, and this is its
  # only backup: the Synology's Hyper Backup task covers four folders
  # (app-home-assistant, ogi-videos, the servarr postgres dump, and
  # homes/hawken/documents), and /volume2/syncthing is not among them.
  #
  # Syncthing is replication, not backup, and the distinction is the point: a
  # delete on any peer propagates to every peer in seconds, and so does
  # anything that encrypts files in place. Per-folder staggered versioning
  # covers a fumbled delete, but it lives on the same volume as the data, so it
  # survives a mistake and not a disk — and monu-cad (1.6GB) has versioning set
  # to none, so it lacks even that.
  #
  # nutmeg holds no copy: restic streams from the mount straight to the
  # repositories, so the only local cost is the metadata cache.
  #
  # Set true once /volume2/syncthing has an NFS export for this host, added in
  # DSM (Control Panel -> Shared Folder -> syncthing -> Edit -> NFS
  # Permissions): read-only, squash "No mapping". Gated because until then the
  # mount does not exist and both restic jobs fail nightly.
  #
  # "No mapping" is load-bearing rather than tidiness: ~100k files under
  # monu-cad are not readable by "other" (the folder is drwxrws---), so under
  # root squashing nutmeg's root maps to the anonymous uid, cannot read them,
  # and the backup reports success while missing most of that folder.
  syncthingBackup = false;

  sshKey = config.age.secrets.restic-ssh-key-nutmeg.path;
  password = config.age.secrets.restic-password-nutmeg.path;

  # Shared by both repos. See the note in secrets/secrets.nix on why one key.
  paths = [
    # Paperless: the EXPORT, not /var/lib/paperless.
    #
    # This host runs paperless against PostgreSQL (PAPERLESS_DBENGINE=postgresql,
    # database.createLocally = true), so the document *metadata* — tags,
    # correspondents, dates, the lot — lives in postgres, not under the data dir.
    # Backing up /var/lib/paperless gets a pile of PDFs with no index, which
    # looks like a working backup and is not. Note the db.sqlite3 in that
    # directory is inert and not the live database, so it is no substitute.
    #
    # document_exporter writes a self-contained, restorable tree: originals plus
    # a manifest carrying everything from the DB. It also stops the paperless
    # services while it runs, so the export is consistent rather than a hot copy.
    config.services.paperless.exporter.directory

    # Home Assistant, minus the two things that dominate its size (see excludes).
    config.users.users.homeassistant.home

    # Matter fabric credentials. 2.4MB of json/ini, and the single worst
    # size-to-pain ratio on this host: losing it means re-pairing every Matter
    # device by hand. No SQLite here, so a plain file copy is safe.
    "/var/lib/home-assistant-matter"

    # AdGuard's hand-tuned config. `data/` is excluded wholesale below — it is
    # ~930MB of query log plus 60MB of filter lists that re-download
    # themselves, and none of it is configuration.
    "/var/lib/private/AdGuardHome"

    # The service-backup output for the whole fleet. This is the cheap way to
    # get every *arr, Plex, Tautulli, beszel, soularr and the tuckles download
    # clients off site: service-backup has already done the hard part, taking
    # transactionally-consistent `sqlite3 .backup` snapshots of live databases,
    # so restic only has to copy the results. Backing up the LIVE dirs instead
    # would mean hot-copying SQLite files that are being written, which is not
    # a backup.
    #
    # Safe from recursion: this is /volume1/app-servarr, while the NAS restic
    # repo lives on /volume1/app-backup — a different share.
    "/mnt/servarr/backups/nutmeg"
    "/mnt/servarr/backups/tuckles"

  ]
  # The Syncthing tree on the NAS — see syncthingBackup above.
  ++ lib.optional syncthingBackup "/mnt/syncthing";

  excludes = [
    # 2.9G of daily ~210MB tarballs whose contents are internally gzipped, so
    # restic dedups them badly — each run would add most of a full copy. They
    # already go to the NAS nightly via the service-backup home-assistant job.
    "${config.users.users.homeassistant.home}/backups"
    "${config.users.users.homeassistant.home}/tmp_backups"

    # The recorder database: 790MB of sensor history that churns constantly, so
    # it too dedups badly. This is a deliberate tradeoff: what survives off
    # site is your *configuration* (.storage — registries, config
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

    # AdGuard: keep AdGuardHome.yaml, drop everything under data/ — 928MB of
    # query log (which also churns completely every day, so it would dedup
    # terribly) and 60MB of filter lists that re-download on demand.
    "/var/lib/private/AdGuardHome/data"

    # ── Exclusions from the service-backup mirror ─────────────────────
    #
    # Without these, mirroring the fleet's backup tree would add ~7.5GB of
    # material that is either regenerable or deliberately excluded elsewhere.
    #
    # The HA tarballs, 2.9GB. These are excluded from the direct HA path above
    # for the same reason: gzipped internally, so each night's ~210MB tarball
    # dedups against its predecessor almost not at all. The NAS copy is their
    # home. Excluded here too, or the mirror would smuggle them back in.
    "/mnt/servarr/backups/nutmeg/home-assistant"

    # Plex's blobs.db, 1.1GB of cached artwork and media metadata that Plex
    # regenerates. library.db — the watch history, ratings and collections,
    # i.e. the part that actually hurts to lose — is 1.1GB and IS kept.
    "/mnt/servarr/backups/nutmeg/plex/com.plexapp.plugins.library.blobs.db"

    # Jellyfin is not a service on this fleet and has no service-backup job, so
    # these 221MB are a leftover directory. Excluded rather than carried; it
    # wants deleting from the NAS.
    "/mnt/servarr/backups/nutmeg/jellyfin"

    # slskd's search cache, 3.1GB of transient Soulseek search results — 96%
    # of that job's footprint and none of its value. transfers.db, events.db
    # and messaging.db are the real state and are kept.
    "/mnt/servarr/backups/tuckles/slskd/search.db"

    # SAB's queued .nzb files: transient by definition, and 155MB of the
    # sabnzbd job's 162MB. history1.db and admin/ are what matter.
    "/mnt/servarr/backups/tuckles/sabnzbd/nzbs"

    # Synology's per-directory thumbnail/index metadata, and service-backup's
    # own zero-byte marker dirs.
    # Synology thumbnail/index metadata, in both the backup tree and the
    # syncthing tree (~123MB of the latter).
    "@eaDir"
    "_selftest_required"
    "_selftest_optional"
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

  # Repos that get a weekly integrity check. `wrapper` is the binary the restic
  # module generates per backup (createWrapper defaults true), pre-loaded with
  # that repo's RESTIC_REPOSITORY and RESTIC_PASSWORD_FILE. Staggered onto
  # different days so two --read-data runs never overlap.
  checkedRepos = {
    nas = {
      wrapper = "/run/current-system/sw/bin/restic-nas";
      schedule = "Mon *-*-* 05:00:00";
    };
  }
  // lib.optionalAttrs enableOffsite {
    offsite = {
      wrapper = "/run/current-system/sw/bin/restic-offsite";
      schedule = "Wed *-*-* 05:00:00";
    };
  };
in
{
  age.secrets.restic-ssh-key-nutmeg.file = ../../secrets/restic-ssh-key-nutmeg.age;
  age.secrets.restic-password-nutmeg.file = ../../secrets/restic-password-nutmeg.age;

  # READ-ONLY, deliberately. restic only ever reads this, and the mount being
  # ro is a hard guarantee that nothing on nutmeg can write into a Syncthing
  # folder by accident — anything that did would replicate to every peer within
  # seconds, which is a much worse failure than a backup not running.
  #
  # NB: this needs an NFS export for /volume2/syncthing on the NAS, added in
  # DSM (Control Panel -> Shared Folder -> syncthing -> Edit -> NFS
  # Permissions). /etc/exports is DSM-managed and gets regenerated when share
  # permissions change, so adding the line by hand would work until it
  # silently did not. If the export disappears the mount fails, the restic
  # jobs fail, and notify-failure says so.
  fileSystems = lib.optionalAttrs syncthingBackup {
    "/mnt/syncthing" = synologyMount "/volume2/syncthing" { readOnly = true; };
  };

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
      # Verification is a separate weekly unit (restic-check-offsite below),
      # not runCheck, so that "the backup broke" and "the repo is corrupt"
      # cannot be confused for one another in the alert.
      runCheck = false;
    });
  };

  # ── Integrity checks ──────────────────────────────────────────────────
  #
  # A backup that runs nightly and is quietly corrupt is worse than no backup,
  # because you believe in it. `restic check --read-data` re-downloads every
  # pack and verifies its hashes, which is the only check that would catch
  # bit-rot or a provider silently mangling a blob; plain `check` verifies
  # structure only and would happily pass over rotten data.
  #
  # This is a SEPARATE unit rather than the backups' own `runCheck` so the two
  # failure modes stay distinguishable: runCheck failing marks the *backup*
  # unit failed, which would have you looking at the wrong thing.
  #
  # Sizing, measured against the live repos: structural check 37s, full
  # --read-data 38s. The cost is almost entirely connection and index overhead
  # rather than data transfer, so the full read is effectively free at this
  # size. Hence --read-data weekly on both repos.
  #
  # Two things to know before reaching for a cheaper scheme:
  #
  #   * rsync.net does NOT provide restic on this account. `restic`, `restic
  #     version` and `borg` all exit 1 with no output through its restricted
  #     shell; only rclone and basic file commands are available. Running the
  #     check server-side is not an option here.
  #   * If a repo grows enough for this to bite, escalate to
  #     --read-data-subset=25%, not to structural-only. A quarter of the data
  #     verified each week still finds rot; structure-only never will.
  # Paperless's exporter stops the paperless services while it runs, and the
  # restic jobs must not start until the export they read has finished. They
  # also now read the service-backup mirror on the NAS, so they need that
  # automount up.
  #
  # Wants/After on the mount, NOT RequiresMountsFor: the share idle-unmounts
  # after 5m, and a hard requirement makes systemd stop a long-running backup
  # the moment that fires. Same lesson as soularr and channel-archive.
  # In practice restic reads the tree continuously, so it keeps the mount busy.
  #
  # Merged into one `systemd.services` definition rather than several, since a
  # bare attribute path cannot be assigned twice in the same attrset.
  systemd.services = {
    restic-backups-nas = {
      after = [ "paperless-exporter.service" servarrMount ] ++ lib.optional syncthingBackup syncthingMount;
      wants = [ servarrMount ] ++ lib.optional syncthingBackup syncthingMount;
    };
  }
  // lib.optionalAttrs enableOffsite {
    restic-backups-offsite = {
      after = [ "paperless-exporter.service" servarrMount ] ++ lib.optional syncthingBackup syncthingMount;
      wants = [ servarrMount ] ++ lib.optional syncthingBackup syncthingMount;
      # Pushes over the WAN; keep it from starving interactive use.
      serviceConfig = {
        IOSchedulingClass = "idle";
        Nice = 10;
      };
    };
  }
  // lib.mapAttrs' (
    name: repo:
    lib.nameValuePair "restic-check-${name}" {
      description = "Verify the integrity of the ${name} restic repository";
      # Ordered after the backup so a check never contends with it for the
      # repository lock; the timers are also hours apart.
      after = [ "restic-backups-${name}.service" ];
      serviceConfig = {
        Type = "oneshot";
        # The generated wrapper already carries RESTIC_REPOSITORY and
        # RESTIC_PASSWORD_FILE, so there is no credential handling here.
        ExecStart = "${repo.wrapper} check --read-data";
        # Verification is never urgent enough to slow down the box.
        Nice = 15;
        IOSchedulingClass = "idle";
      };
    }
  ) checkedRepos;

  systemd.timers = lib.mapAttrs' (
    name: repo:
    lib.nameValuePair "restic-check-${name}" {
      description = "Weekly integrity check of the ${name} restic repository";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = repo.schedule;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    }
  ) checkedRepos;

  # Both restic jobs and the exporter they depend on. A silent backup failure is
  # the worst kind, since you find out when you need the backup.
  services.notifyFailure.units = [
    "restic-backups-nas.service"
    "paperless-exporter.service"
  ]
  # Only watch the offsite unit when it actually exists; naming a non-existent
  # unit here would quietly define an empty stub (see notify-failure.nix).
  ++ lib.optional enableOffsite "restic-backups-offsite.service"
  # A check that fails is the single most important alert here: it means the
  # backups you have been trusting are not restorable.
  ++ map (n: "restic-check-${n}.service") (lib.attrNames checkedRepos);

  # …and a heartbeat, because a check unit that silently stops being scheduled
  # looks exactly like one that keeps passing. Weekly cadence + 1h jitter, so
  # 8 days is the tightest interval that cannot false-alarm.
  services.unitHeartbeat.units = map (n: {
    unit = "restic-check-${n}.service";
    interval = 691200; # 8 days
  }) (lib.attrNames checkedRepos);

  # `restic-nas` / `restic-offsite` wrappers land in PATH (createWrapper
  # defaults true), pre-set with the repo and password, for restores:
  #   restic-nas snapshots
  #   restic-nas restore latest --target /tmp/restore
  environment.systemPackages = [ pkgs.restic ];

  # Assert the exporter directory is actually inside what we back up, so a
  # future change to either can't silently decouple them.
  assertions = [
    {
      assertion = lib.elem config.services.paperless.exporter.directory paths;
      message = "restic.nix: paperless export dir is not in the restic paths";
    }
  ];
}
