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
{ lib, config, pkgs, utils, ... }:
let
  cfg = config.services.channelArchive;

  nfoGenerator = ./nfo.py;

  channelModule = lib.types.submodule ({ name, ... }: {
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
  });

  serviceName = name: "channel-archive-${name}";

  mkService = name: ch:
    let
      metaArgs = lib.optionals ch.writeMetadata [
        "--write-info-json"
        # Per-video metadata only: without this, yt-dlp also writes a
        # playlist-level "<channel> [<id>].info.json", and nfo.py then emits a
        # junk .nfo for the playlist itself. Suppress the playlist metafiles.
        "--no-write-playlist-metafiles"
        "--write-thumbnail"
        "--convert-thumbnails" "jpg"
        "--embed-metadata"
      ];
      formatArgs = lib.optionals (ch.format != "") [ "-f" ch.format ];
      rateLimitArgs = lib.optionals ch.rateLimit [
        "--sleep-requests" "1.5"
        "--min-sleep-interval" "5"
        "--max-sleep-interval" "30"
      ];
      ytdlpArgs = lib.concatStringsSep " " (map lib.escapeShellArg (
        [
          "--download-archive" "${ch.destination}/archive.txt"
          "--output" "${ch.destination}/%(title)s [%(id)s].%(ext)s"
          "--no-overwrites"
          "--continue"
        ]
        ++ formatArgs
        ++ metaArgs
        ++ rateLimitArgs
        ++ ch.extraArgs
        ++ [ ch.url ]
      ));
      # /mnt/channels is an all_squash NFS export: every write (even root's) maps
      # to the anon uid 1024:users. The parent bucket dir is group-writable to
      # `users` and ReadWritePaths grants the sandbox that parent, so the service
      # creates its own destination dir here — no manual NAS-side setup needed.
      # Runs with NO `+` prefix — inside the sandbox as the DynamicUser
      # (SupplementaryGroups=users) — so mkdir/`-w` match what yt-dlp will see.
      # setgid on the parent propagates group `users` to the new dir.
      preStart = pkgs.writeShellScript "channel-archive-${name}-pre" ''
        mkdir -p ${lib.escapeShellArg ch.destination} 2>/dev/null || true
        if [ ! -d ${lib.escapeShellArg ch.destination} ] || [ ! -w ${lib.escapeShellArg ch.destination} ]; then
          echo "channel-archive: destination ${ch.destination} missing or not writable — ensure its parent bucket exists on the NAS and is group-writable to 'users'" >&2
          exit 1
        fi
      '';
    in {
      description = "Archive channel ${name} with yt-dlp";
      # Soft Wants/After on the mount unit (NOT RequiresMountsFor) — a run can
      # outlast the autofs NFS's 5m idle-unmount, and a hard Requires would make
      # systemd SIGTERM the service when the mount idle-unmounts mid-run. Wants
      # doesn't propagate the stop; the automount transparently re-mounts on
      # access. Same rationale as soularr (hosts/nutmeg/soulseek.nix).
      after = [ "network-online.target" "${utils.escapeSystemdPath cfg.baseDir}.mount" ];
      wants = [ "network-online.target" "${utils.escapeSystemdPath cfg.baseDir}.mount" ];
      path = [ pkgs.yt-dlp pkgs.ffmpeg pkgs.python3 pkgs.coreutils pkgs.gnugrep ];
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
        ReadWritePaths = [ ''"${builtins.dirOf ch.destination}"'' ];
        # Give yt-dlp a writable HOME for its cache (~/.cache/yt-dlp) under the
        # DynamicUser state dir, else the read-only HOME emits cache warnings.
        StateDirectory = "channel-archive-${name}";
        Environment = [ "HOME=/var/lib/channel-archive-${name}" ];
      };
      script = ''
        set -uo pipefail
        rc=0
        out="$(mktemp)"
        yt-dlp ${ytdlpArgs} 2>&1 | tee "$out" || rc=$?
        if grep -qiE 'HTTP Error 429|Sign in to confirm|not a bot|HTTP Error 403' "$out"; then
          echo "channel-archive: >>> BLOCKED/RATE-LIMITED by YouTube (429/403/bot-check) <<<" >&2
          rc=75
        fi
        rm -f "$out"
        ${lib.optionalString ch.writeNfo ''
          python3 ${nfoGenerator} ${lib.escapeShellArg ch.destination} || true
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
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--concurrent-fragments" "4" "--retries" "10" ];
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
  };

  config = lib.mkIf cfg.enable {
    # Only enabled channels render units; declared-but-disabled ones are inert.
    systemd.services = lib.mapAttrs'
      (name: ch: lib.nameValuePair (serviceName name) (mkService name ch))
      (lib.filterAttrs (_: ch: ch.enable) cfg.channels);

    systemd.timers = lib.mapAttrs'
      (name: ch: lib.nameValuePair (serviceName name) (mkTimer name ch))
      (lib.filterAttrs (_: ch: ch.enable) cfg.channels);
  };
}
