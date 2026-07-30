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
    };
  });

  serviceName = name: "channel-archive-${name}";

  mkService = name: ch:
    let
      metaArgs = lib.optionals ch.writeMetadata [
        "--write-info-json"
        "--write-thumbnail"
        "--convert-thumbnails" "jpg"
        "--embed-metadata"
      ];
      formatArgs = lib.optionals (ch.format != "") [ "-f" ch.format ];
      ytdlpArgs = lib.concatStringsSep " " (map lib.escapeShellArg (
        [
          "--download-archive" "${ch.destination}/archive.txt"
          "--output" "${ch.destination}/%(title)s [%(id)s].%(ext)s"
          "--no-overwrites"
          "--continue"
        ]
        ++ formatArgs
        ++ metaArgs
        ++ ch.extraArgs
        ++ [ ch.url ]
      ));
      # /mnt/channels is a root-squash NFS export: even root can't chown/chmod
      # there, so we can't create/fix up the destination dir ourselves. Instead,
      # fail fast (before yt-dlp runs) if it's missing or not writable. Runs
      # with NO `+` prefix — inside the sandbox as the DynamicUser, through
      # ReadWritePaths — so the `-w` check reflects what yt-dlp will actually
      # see, not root's (irrelevant, root-squashed) view of the mount.
      preStart = pkgs.writeShellScript "channel-archive-${name}-pre" ''
        if [ ! -d ${lib.escapeShellArg ch.destination} ]; then
          echo "channel-archive: destination ${ch.destination} does not exist — create it on the NAS (group 'users', group-writable) first" >&2
          exit 1
        fi
        if [ ! -w ${lib.escapeShellArg ch.destination} ]; then
          echo "channel-archive: destination ${ch.destination} not writable by the service user (needs group 'users' + group-write)" >&2
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
      path = [ pkgs.yt-dlp pkgs.ffmpeg pkgs.python3 ];
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
        # DynamicUser implies ProtectSystem=strict (so /mnt is read-only) — carve out
        # the destination so yt-dlp can write videos, archive.txt, and metadata.
        ReadWritePaths = [ ch.destination ];
        # Give yt-dlp a writable HOME for its cache (~/.cache/yt-dlp) under the
        # DynamicUser state dir, else the read-only HOME emits cache warnings.
        StateDirectory = "channel-archive-${name}";
        Environment = [ "HOME=/var/lib/channel-archive-${name}" ];
      };
      script = ''
        set -uo pipefail
        rc=0
        yt-dlp ${ytdlpArgs} || rc=$?
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
      RandomizedDelaySec = "1h";
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
    channels = lib.mkOption {
      type = lib.types.attrsOf channelModule;
      default = { };
      description = "Channels to archive, keyed by name.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.mapAttrs'
      (name: ch: lib.nameValuePair (serviceName name) (mkService name ch))
      cfg.channels;

    systemd.timers = lib.mapAttrs'
      (name: ch: lib.nameValuePair (serviceName name) (mkTimer name ch))
      cfg.channels;
  };
}
