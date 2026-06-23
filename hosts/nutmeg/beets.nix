{
  pkgs,
  config,
  utils,
  ...
}:
let
  # The music share's systemd mount-unit name, derived from the path rather than
  # hand-spelled ("mnt-music.mount") — escapeSystemdPath does the dash/escape
  # mangling for us, so it stays correct if the mountpoint ever changes.
  musicMount = "${utils.escapeSystemdPath "/mnt/music"}.mount";

  # Config lives in the store (immutable, in git), generated from a Nix attrset so
  # there's no YAML quoting/indent footgun. Surfaced at $BEETSDIR/config.yaml via a
  # tmpfiles symlink (below) so `beet` finds it natively for manual fix-up runs.
  beetsConfig = (pkgs.formats.yaml { }).generate "beets-config.yaml" {
    directory = "/mnt/music/data"; # files already live here; Lidarr owns the layout
    library = "/var/lib/beets/library.db";

    import = {
      copy = false; # NEVER relocate/rename — Lidarr tracks paths in its own DB
      move = false;
      write = true; # embed canonical tags in place
      incremental = true; # `import -A` skips already-added dirs; cheap to re-walk
      quiet = true; # non-interactive
      resume = false;
      log = "/var/lib/beets/import.log";
    };

    # Bonus — the other half of Lidarr #2105: write ORIGINALDATE/ORIGINALYEAR so a
    # remaster sorts by the album's original release, not the reissue date.
    original_date = true;

    # `musicbrainz` (default-enabled, but listing `plugins` overrides the default
    # so it must be named) is the MB lookup that `mbsync` uses to pull canonical
    # data by the embedded MBID.
    plugins = [
      "musicbrainz"
      "mbsync"
    ];
  };

  # mbsync mode: don't fuzzy-match (which skips collaborative/partial albums) —
  # trust the MBID Lidarr embedded and pull MB-canonical data from it.
  #   1. import -A: add new albums *as-is* (no matching → no skips), recording
  #      their embedded MBIDs. `incremental` skips already-added dirs (no network).
  #   2. mbsync: re-fetch by MBID and write canonical tags (incl. *_sort), but only
  #      for items not yet synced (empty artist_sort), so steady-state runs don't
  #      re-hit MusicBrainz for the whole library.
  beetsSync = pkgs.writeShellScript "beets-sync-run" ''
    set -euo pipefail
    beet=${pkgs.beets}/bin/beet
    "$beet" import --noautotag --quiet /mnt/music/data
    # --nomove is critical: mbsync renames files to the beets path format by
    # default when they're inside the library `directory` (= /mnt/music/data),
    # which would destroy Lidarr's layout. We only ever rewrite tags in place.
    "$beet" mbsync --nomove 'artist_sort::^$'
  '';

  # Lidarr's "On Import"/"On Upgrade" custom script. It does NOT run beet itself —
  # it pokes the one beets-sync unit, so the timer and Lidarr can never spawn two
  # beet processes (which would collide on MusicBrainz's 1 req/s/IP limit and the
  # single-writer SQLite library.db). systemd coalesces concurrent starts.
  beetsTrigger = pkgs.writeShellScript "lidarr-beets-trigger" ''
    [ "''${lidarr_eventtype:-}" = "Test" ] && exit 0
    exec ${pkgs.systemd}/bin/systemctl start --no-block beets-sync.service
  '';

  # Lidarr's tagging settings + connections live in lidarr.db (no NixOS option),
  # so we enforce them via the API on every boot — same "pin runtime config in
  # git" intent as the bazarr/seerr ExecStartPre pins, but Lidarr's are behind the
  # running API, so this is a separate unit that waits for it to come up.
  lidarrPin = pkgs.writeShellScript "lidarr-beets-pin" ''
    set -euo pipefail
    key=$(${pkgs.gnused}/bin/sed -n 's/.*APIKEY=//p' ${config.age.secrets.lidarr-api-key.path})
    api=http://127.0.0.1:8686/api/v1
    req() { ${pkgs.curl}/bin/curl -fsS -H "X-Api-Key: $key" "$@"; }
    jq() { ${pkgs.jq}/bin/jq "$@"; }

    # wait for Lidarr's API (up to ~60s)
    for _ in $(${pkgs.coreutils}/bin/seq 60); do
      req "$api/system/status" >/dev/null 2>&1 && break
      ${pkgs.coreutils}/bin/sleep 1
    done

    # 1. Lidarr tagging policy:
    #    - scrubAudioTags=false: stop it deleting beets' *_sort (and other) tags.
    #    - writeAudioTags=newFiles: stamp tags (incl. MBIDs) on import only, not on a
    #      continuous "sync" — so Lidarr seeds the MBID beets needs but stops
    #      reverting beets' canonical artist/title back to its own massaged values.
    req "$api/config/metadataprovider" \
      | jq '.scrubAudioTags = false | .writeAudioTags = "newFiles"' \
      | req -X PUT "$api/config/metadataprovider" -H 'Content-Type: application/json' -d @- >/dev/null

    # 2. upsert the beets-sync custom-script connection (idempotent by name)
    if ! req "$api/notification" | jq -e '.[] | select(.name == "beets-sync")' >/dev/null; then
      req "$api/notification/schema" \
        | jq --arg path "${beetsTrigger}" '
            ( map(select(.implementation == "CustomScript")) | .[0] )
            | .name = "beets-sync"
            | .onReleaseImport = true
            | .onUpgrade = true
            | ( .fields |= map(if .name == "path" then .value = $path else . end) )
          ' \
        | req -X POST "$api/notification?forceSave=true" -H 'Content-Type: application/json' -d @- >/dev/null
    fi
  '';
in
{
  users.groups.beets = { };
  users.users.beets = {
    isSystemUser = true;
    group = "beets";
    # gid 100 ("users") → inherit the group-write the NAS grants on the media tree,
    # exactly like the *arr service users in servarr.nix.
    extraGroups = [ "users" ];
    home = "/var/lib/beets";
  };

  # State dir + the immutable config symlink ($BEETSDIR/config.yaml → store).
  systemd.tmpfiles.rules = [
    "d /var/lib/beets 0750 beets beets -"
    "L+ /var/lib/beets/config.yaml - - - - ${beetsConfig}"
  ];

  # Let the lidarr user start (only) this one unit, for the custom-script trigger.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "beets-sync.service" &&
          subject.user == "lidarr") {
        return polkit.Result.YES;
      }
    });
  '';

  # ── beets-sync: write MB-canonical tags in place from each file's MBID ──
  systemd.services.beets-sync = {
    description = "Write MB-canonical tags (incl. sort-names) via beets mbsync";
    # Wants/After, NOT Requires: the NFS share idle-unmounts after 5m and a hard
    # mount dep would SIGTERM a long run — same lesson as soularr. beets reads
    # /mnt continuously so it won't actually idle out, but stay safe.
    after = [
      "network-online.target"
      musicMount
    ];
    wants = [
      "network-online.target"
      musicMount
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "beets";
      Group = "beets";
      SupplementaryGroups = [ "users" ];
      Environment = "BEETSDIR=/var/lib/beets";
      # First run mbsyncs the whole library at MusicBrainz's ~1 req/s — hours.
      TimeoutStartSec = "infinity";
      ExecStart = beetsSync;
    };
  };

  systemd.timers.beets-sync = {
    description = "Periodic beets re-tag (backstop for the Lidarr trigger)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Every 4h — just a backstop now that the Lidarr custom script triggers a
      # run on each import/upgrade.
      OnCalendar = "0/4:00";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };

  # ── Enforce Lidarr's scrub-off + custom-script connection on every boot ──
  systemd.services.lidarr-beets-pin = {
    description = "Pin Lidarr tagging config + beets-sync connection (for beets)";
    after = [ "lidarr.service" ];
    wants = [ "lidarr.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = lidarrPin; # runs as root to read the root-owned api-key secret
    };
  };
}
