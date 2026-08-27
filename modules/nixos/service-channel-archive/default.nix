# Incremental yt-dlp channel archiver. One oneshot service + timer per channel;
# per-channel `--download-archive` dedups. `baseDir` (/mnt/channels) is a
# root-squash NFS export, so this module cannot chown/chmod/create dirs there
# even as root — each channel's destination dir must already exist on the NAS,
# owned by group `users` and group-writable. Downloads land world-readable
# (UMask 0022 -> 644 files) matching the rest of the tree, so Plex/Jellyfin
# read them via the `other` bit; SupplementaryGroups=[ "users" ] is what lets
# the service itself write into the group-writable dest dir and append
# archive.txt. Optionally writes .info.json/thumbnail metadata and generates
# Kodi/Jellyfin .nfo files.
{
  lib,
  config,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.services.channelArchive;

  nfoGenerator = ./nfo.py;
  restructureScript = ./restructure.py;
  channelArtworkScript = ./channel-artwork.py;

  # `channel-archive-status`: read-only report over the archivers. Reads systemd
  # state, the journal, archive.txt and the destination dirs -- no network calls,
  # deliberately (see the docstring), so running it can never be what trips the
  # YouTube bot-check the units already have to handle.
  statusScript = pkgs.writeShellApplication {
    name = "channel-archive-status";
    runtimeInputs = [
      pkgs.python3
      pkgs.systemd
    ];
    text = ''
      exec python3 ${./status.py} "$@"
    '';
  };

  channelModule = lib.types.submodule (
    { name, ... }: {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to render this channel's service + timer. Default false, so a
            channel can be declared (staged) in config without archiving until
            flipped to true — useful for tracking a backlog of channels to enable
            in batches.
          '';
        };
        url = lib.mkOption {
          type = lib.types.str;
          description = "Channel or playlist URL passed to yt-dlp.";
        };
        destination = lib.mkOption {
          type = lib.types.str;
          default = "${cfg.baseDir}/${name}";
          defaultText = lib.literalMD "`\${baseDir}/<name>`";
          description = "Directory downloads and archive.txt live in.";
        };
        schedule = lib.mkOption {
          type = lib.types.str;
          default = cfg.schedule;
          defaultText = lib.literalExpression "config.services.channelArchive.schedule";
          description = "systemd OnCalendar for this channel.";
        };
        format = lib.mkOption {
          type = lib.types.str;
          default = cfg.format;
          defaultText = lib.literalExpression "config.services.channelArchive.format";
          description = "yt-dlp -f selector ('' = yt-dlp default).";
        };
        writeMetadata = lib.mkOption {
          type = lib.types.bool;
          default = cfg.writeMetadata;
          defaultText = lib.literalExpression "config.services.channelArchive.writeMetadata";
          description = "Write .info.json + thumbnail + embedded metadata.";
        };
        writeNfo = lib.mkOption {
          type = lib.types.bool;
          default = cfg.writeNfo;
          defaultText = lib.literalExpression "config.services.channelArchive.writeNfo";
          description = "Generate Kodi/Jellyfin .nfo from .info.json.";
        };
        includeLive = lib.mkOption {
          type = lib.types.bool;
          default = cfg.includeLive;
          defaultText = lib.literalExpression "config.services.channelArchive.includeLive";
          description = "Download livestreams or not";
        };
        restructure = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "After download, reshape new files into the Plex date-based TV layout (Season/SxxExx) and finalize them in Plex. Opt-in; leave off for music/artist channels.";
        };
        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = cfg.extraArgs;
          defaultText = lib.literalExpression "config.services.channelArchive.extraArgs";
          description = "Extra yt-dlp arguments for this channel.";
        };
        rateLimit = lib.mkOption {
          type = lib.types.bool;
          default = cfg.rateLimit;
          defaultText = lib.literalExpression "config.services.channelArchive.rateLimit";
          description = "Inject polite YouTube pacing flags (--sleep-requests + --min/max-sleep-interval) to reduce rate-limit/bot-block risk.";
        };
      };
    }
  );

  serviceName = name: "channel-archive-${name}";

  mkService =
    name: ch:
    let
      metaArgs = lib.optionals ch.writeMetadata [
        "--write-info-json"
        # Per-video metadata only: without this, yt-dlp also writes a
        # playlist-level "<channel> [<id>].info.json", and nfo.py then emits a
        # junk .nfo for the playlist itself. Suppress the playlist metafiles.
        "--no-write-playlist-metafiles"
        "--write-thumbnail"
        "--convert-thumbnails"
        "jpg"
        "--embed-metadata"
      ];
      formatArgs = lib.optionals (ch.format != "") [
        "-f"
        ch.format
      ];
      rateLimitArgs = lib.optionals ch.rateLimit [
        "--sleep-requests"
        "1.5"
        "--min-sleep-interval"
        "5"
        "--max-sleep-interval"
        "30"
      ];
      # Skip live/premiere content: currently-live streams, scheduled premieres,
      # and past-live VODs (was_live/post_live). Shorts need no filter — the
      # channel URLs target the `/videos` tab, which never lists Shorts.
      liveFilterArgs = lib.optionals (!ch.includeLive) [
        "--match-filter"
        "live_status != is_live & live_status != is_upcoming & live_status != was_live & live_status != post_live"
      ];
      credArgs = lib.optionals (ch.restructure && cfg.plexTokenFile != null) [
        "plex-token:${cfg.plexTokenFile}"
      ];
      ytdlpArgs = lib.concatStringsSep " " (
        map lib.escapeShellArg (
          [
            "--download-archive"
            "${ch.destination}/archive.txt"
            "--output"
            "${ch.destination}/%(title)s [%(id)s].%(ext)s"
            "--no-overwrites"
            "--continue"
            # fetch live streams from the beginning
            "--live-from-start"
            # Stop at the first error instead of limping through the rest of
            # the playlist (see the fifo-vs-plain-pipe comment in `script`
            # below) — channel listings are newest-first, so if that first
            # error is a genuine bot-block, this caps the run to one item
            # instead of hundreds. The flip side (a permanently-broken newest
            # video wedging the channel forever) is what alertUser's
            # notification exists to catch.
            "--abort-on-error"
            # yt-dlp spawns ffmpeg/ffprobe itself for merging and thumbnail
            # conversion, resolving them off PATH -- substitution in `script`
            # cannot reach that. Pin the location so the ffmpeg doing the
            # muxing is the one this module depends on, not whatever PATH
            # happens to surface first.
            "--ffmpeg-location"
            "${pkgs.ffmpeg}/bin"
          ]
          ++ formatArgs
          ++ metaArgs
          ++ rateLimitArgs
          ++ liveFilterArgs
          ++ ch.extraArgs
          ++ [ ch.url ]
        )
      );
      # /mnt/channels is an all_squash NFS export: every write (even root's) maps
      # to the anon uid 1024:users. The parent bucket dir is group-writable to
      # `users` and ReadWritePaths grants the sandbox that parent, so the service
      # creates its own destination dir here — no manual NAS-side setup needed.
      # Runs with NO `+` prefix — inside the sandbox as the DynamicUser
      # (SupplementaryGroups=users) — so mkdir/`-w` match what yt-dlp will see.
      # setgid on the parent propagates group `users` to the new dir.
      preStart = pkgs.writeShellScript "channel-archive-${name}-pre" ''
        ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg ch.destination} 2>/dev/null || true
        if [ ! -d ${lib.escapeShellArg ch.destination} ] || [ ! -w ${lib.escapeShellArg ch.destination} ]; then
          echo "channel-archive: destination ${ch.destination} missing or not writable — ensure its parent bucket exists on the NAS and is group-writable to 'users'" >&2
          exit 1
        fi

        # Discard download fragments left behind by an EARLIER run. yt-dlp's
        # --continue will happily resume a .part from days ago, but YouTube's
        # media URLs and encodes do not stay byte-compatible that long. On
        # 2026-08-26 videogamedunkey resumed a 13-day-old AV1 .part, produced a
        # byte-complete but corrupt .f399.mp4, and ffmpeg died muxing it with
        # "Postprocessing: Conversion failed!". --abort-on-error then killed the
        # run -- and since the corrupt fragment persisted, every later run hit
        # the same wall, so one bad file wedged ~999 videos behind it. The 94
        # sibling .part files in that folder were all queued to do the same.
        #
        # Only fragments older than the window below are removed. mtime advances
        # while a download is in flight, so an actively-written fragment is
        # never eligible; the window only has to exceed how long a *sibling*
        # unit sharing this destination might stall on one file (VODs + clips
        # deliberately share a folder). Observed runs top out around 25min.
        # -print so the journal records what was swept rather than doing it
        # silently.
        ${pkgs.findutils}/bin/find ${lib.escapeShellArg ch.destination} -maxdepth 1 -regextype posix-extended \
          \( -name '*.part' -o -name '*.ytdl' -o -name '*.temp.*' \
             -o -regex '.*\.f[0-9]+(-[0-9]+)?\.(mp4|webm|m4a|mkv|opus|mp3)' \) \
          -mmin +360 -print -delete 2>/dev/null || true
      '';
    in
    {
      description = "Archive channel ${name} with yt-dlp";
      # Soft Wants/After on the mount unit (NOT RequiresMountsFor) — a run can
      # outlast the autofs NFS's 5m idle-unmount, and a hard Requires would make
      # systemd SIGTERM the service when the mount idle-unmounts mid-run. Wants
      # doesn't propagate the stop; the automount transparently re-mounts on
      # access. Same rationale as soularr (hosts/nutmeg/soulseek.nix).
      after = [
        "network-online.target"
        "${utils.escapeSystemdPath cfg.baseDir}.mount"
      ];
      wants = [
        "network-online.target"
        "${utils.escapeSystemdPath cfg.baseDir}.mount"
      ];
      path = [
        pkgs.yt-dlp
        pkgs.ffmpeg
        pkgs.python3
        pkgs.coreutils
        pkgs.gnugrep
      ]
      ++ lib.optionals ch.restructure [
        # channel-artwork.py shells out to bare `magick` via bash -c, so this
        # must stay on PATH. dejavu_fonts does NOT belong here -- it ships no
        # binaries; the font reaches the script via CAW_FONT below.
        pkgs.imagemagick
      ];
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        # Grants group-write into the (pre-existing, group `users`) destination
        # dir and append access to its group-writable archive.txt — this, not
        # ownership, is how the DynamicUser can write under root-squash NFS.
        SupplementaryGroups = [ "users" ];
        # 0022 -> files land 644 (other-readable), matching the existing
        # youtube/pinchflat tree, so Plex/Jellyfin (reading via `other`, not
        # group) can see new downloads regardless of their own group membership.
        UMask = "0022";
        # No `+` prefix: must run as the DynamicUser inside the sandbox (see
        # preStart above) so its writability check is meaningful.
        ExecStartPre = preStart;
        # DynamicUser implies ProtectSystem=strict (so /mnt is read-only) — carve
        # out the parent bucket (NOT just the dest) so the service can create its
        # own destination dir under it (see preStart) as well as write videos,
        # archive.txt, and metadata. Binding the parent — which always pre-exists
        # — instead of the dest is what lets a brand-new channel work with zero
        # manual NAS-side dir creation. Quoted as one token in case a bucket path
        # ever contains a space; systemd unquotes it back to the single path.
        ReadWritePaths = [
          ''"${builtins.dirOf ch.destination}"''
        ]
        ++ lib.optionals (cfg.alertUser != null) [
          "/var/mail"
          "/var/lib/channel-archive-alerts"
        ];
        # Give yt-dlp a writable HOME for its cache (~/.cache/yt-dlp) under the
        # DynamicUser state dir, else the read-only HOME emits cache warnings.
        StateDirectory = "channel-archive-${name}";
        Environment = [ "HOME=/var/lib/channel-archive-${name}" ];
        LoadCredential = credArgs;
      };
      script = ''
        set -uo pipefail
        rc=0
        out="$(${pkgs.coreutils}/bin/mktemp)"
        # --abort-on-error (see ytdlpArgs) already stops the whole run at the
        # first error, so there's no more "grind through hundreds of items"
        # case to cut off early — a plain pipe + post-hoc grep is enough now.
        ${pkgs.yt-dlp}/bin/yt-dlp ${ytdlpArgs} 2>&1 | ${pkgs.coreutils}/bin/tee "$out" || rc=$?
        if ${pkgs.gnugrep}/bin/grep -qiE 'HTTP Error 429|Sign in to confirm|not a bot|HTTP Error 403' "$out"; then
          echo "channel-archive: >>> BLOCKED/RATE-LIMITED by YouTube (429/403/bot-check) <<<" >&2
          rc=75
        fi
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 75 ]; then
          ${lib.optionalString (cfg.alertUser != null) ''
            # Something other than the known bot-check/rate-limit case killed
            # this run (crash, bad args, an extractor error yt-dlp didn't skip
            # past) — flag it instead of silently retrying-and-failing on every
            # future timer run. Local mbox mail + a note in the fish greeting
            # for now; swap in a real notification channel (Telegram, etc.)
            # later.
            {
              echo "From channel-archive@${config.networking.hostName}  $(${pkgs.coreutils}/bin/date)"
              echo "Date: $(${pkgs.coreutils}/bin/date -R)"
              echo "From: channel-archive <channel-archive@${config.networking.hostName}>"
              echo "To: ${cfg.alertUser}@${config.networking.hostName}"
              echo "Subject: channel-archive: ${name} failed (exit $rc)"
              echo
              echo "${name} exited $rc — not the known 429/403/bot-check case."
              echo "Last output:"
              ${pkgs.coreutils}/bin/tail -n 15 "$out"
              echo
            } >> /var/mail/${cfg.alertUser} 2>/dev/null || true
            echo "$(${pkgs.coreutils}/bin/date -R): ${name} failed (exit $rc) — journalctl -u channel-archive-${name} -n 100" >> /var/lib/channel-archive-alerts/notices 2>/dev/null || true
          ''}
        fi
        ${pkgs.coreutils}/bin/rm -f "$out"
        ${lib.optionalString ch.writeNfo ''
          ${pkgs.python3}/bin/python3 ${nfoGenerator} ${lib.escapeShellArg ch.destination} || true
        ''}
        ${lib.optionalString ch.restructure ''
          ${pkgs.python3}/bin/python3 ${restructureScript} ${lib.escapeShellArg ch.destination} \
            ${
              lib.optionalString (cfg.plexSection != null) "--section ${lib.escapeShellArg cfg.plexSection}"
            } \
            --url ${lib.escapeShellArg cfg.plexUrl} \
            ${
              lib.optionalString (cfg.plexTokenFile != null) ''--token-file "$CREDENTIALS_DIRECTORY/plex-token"''
            } \
            || true
          CAW_FONT=${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf \
          ${pkgs.python3}/bin/python3 ${channelArtworkScript} ${lib.escapeShellArg ch.destination} \
            ${
              lib.optionalString (cfg.plexSection != null) "--section ${lib.escapeShellArg cfg.plexSection}"
            } \
            --url ${lib.escapeShellArg cfg.plexUrl} \
            ${
              lib.optionalString (cfg.plexTokenFile != null) ''--token-file "$CREDENTIALS_DIRECTORY/plex-token"''
            } \
            || true
        ''}
        exit "$rc"
      '';
    };

  mkTimer = name: ch: {
    description = "Timer: archive channel ${name}";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = ch.schedule;
      Persistent = true;
      # Wide spread so many channels don't all hit YouTube at once (raising
      # bot-block risk) — each fires at a stable random offset within 18h.
      RandomizedDelaySec = "18h";
    };
  };
in
{
  options.services.channelArchive = {
    enable = lib.mkEnableOption "incremental yt-dlp channel archiving";

    baseDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/channels";
      description = "Base dir; each channel downloads to <baseDir>/<name>.";
    };
    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Default systemd OnCalendar for channels.";
    };
    format = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Default yt-dlp -f selector ('' = yt-dlp default).";
    };
    writeMetadata = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Default: write .info.json + thumbnail + embedded metadata.";
    };
    writeNfo = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Default: generate Kodi/Jellyfin .nfo from .info.json.";
    };
    includeLive = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Download livestreams or not";
    };
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--concurrent-fragments"
        "4"
        "--retries"
        "10"
      ];
      description = "Default extra yt-dlp arguments.";
    };
    rateLimit = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Default: inject polite YouTube pacing flags to reduce rate-limit/bot-block risk.";
    };
    channels = lib.mkOption {
      type = lib.types.attrsOf channelModule;
      default = { };
      description = "Channels to archive, keyed by name.";
    };
    plexUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:32400";
      description = "Plex base URL for restructure finalize.";
    };
    plexSection = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Plex library section id containing restructured shows.";
    };
    plexTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to a file holding the Plex token (e.g. an age secret). Loaded into the unit via LoadCredential.";
    };
    alertUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Local user to notify when a channel run fails for a reason other than
        the known 429/403/bot-check case (that one is expected to self-resolve
        on the channel's next timer run and isn't alerted on). Delivers a
        local mbox message to /var/mail/<alertUser> and appends a one-line
        note to /var/lib/channel-archive-alerts/notices, which fish prints on
        the next interactive login. null disables notifications.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # Only enabled channels render units; declared-but-disabled ones are inert.
        systemd.services = lib.mapAttrs' (
          name: ch: lib.nameValuePair (serviceName name) (mkService name ch)
        ) (lib.filterAttrs (_: ch: ch.enable) cfg.channels);

        systemd.timers = lib.mapAttrs' (name: ch: lib.nameValuePair (serviceName name) (mkTimer name ch)) (
          lib.filterAttrs (_: ch: ch.enable) cfg.channels
        );

        environment.systemPackages = [ statusScript ];
      }
      (lib.mkIf (cfg.alertUser != null) {
        # /var/mail 1777 like /tmp: any DynamicUser service may need to touch
        # it. The mailbox file itself is pre-created 0660 alertUser:users so
        # appends work via the `users` supplementary group the archive services
        # already have — same group-write trick archive.txt uses.
        systemd.tmpfiles.rules = [
          "d /var/mail 1777 root root - -"
          "f /var/mail/${cfg.alertUser} 0660 ${cfg.alertUser} users - -"
          "d /var/lib/channel-archive-alerts 2775 ${cfg.alertUser} users - -"
          "f /var/lib/channel-archive-alerts/notices 0664 ${cfg.alertUser} users - -"
        ];
        programs.fish.interactiveShellInit = ''
          if test -s /var/lib/channel-archive-alerts/notices
            echo "⚠ channel-archive alerts (unread):"
            cat /var/lib/channel-archive-alerts/notices
            echo "(clear with: rm /var/lib/channel-archive-alerts/notices)"
          end
        '';
      })
    ]
  );
}
