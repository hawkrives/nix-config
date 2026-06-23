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
      write = true; # embed tags (incl. artist_sort / albumartist_sort) in place
      incremental = true; # remember done dirs; cheap to re-walk the whole tree
      quiet = true; # non-interactive
      quiet_fallback = "skip"; # uncertain match? skip it — never guess a wrong sort
      resume = false;
      log = "/var/lib/beets/import.log";
    };

    # MBIDs Lidarr embeds make matches near-exact; auto-accept strong ones.
    match.strong_rec_thresh = 0.1;

    # Bonus — the other half of Lidarr #2105: write ORIGINALDATE/ORIGINALYEAR so a
    # remaster sorts by the album's original release, not the reissue date.
    original_date = true;

    # `musicbrainz` is the autotagger/candidate source — default-enabled, but
    # setting `plugins` at all overrides that default, so it MUST be listed
    # explicitly or every album matches 0 candidates and skips. `mbsync` adds the
    # on-demand `beet mbsync -W` re-pull later.
    plugins = [
      "musicbrainz"
      "mbsync"
    ];
  };

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

    # 1. stop Lidarr scrubbing foreign tags (it deletes beets' *_sort tags). Leave
    #    writeAudioTags alone — the MBIDs Lidarr writes help beets match.
    req "$api/config/metadataprovider" \
      | jq '.scrubAudioTags = false' \
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

  # ── beets-sync: tag the library in place (adds the sort tags Lidarr omits) ──
  systemd.services.beets-sync = {
    description = "Embed sort-name tags Lidarr omits (beets, in place)";
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
      # First run walks the whole tree at MusicBrainz's ~1 req/s — can take hours.
      TimeoutStartSec = "infinity";
      # -R / --incremental-skip-later: don't record *skipped* albums in the
      # incremental state, so a transiently-skipped album (low-confidence match,
      # MB blip) is retried next run instead of being stuck forever. Matched
      # albums are still recorded, so steady-state runs only re-check the skip set.
      ExecStart = "${pkgs.beets}/bin/beet import --quiet --incremental-skip-later /mnt/music/data";
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
