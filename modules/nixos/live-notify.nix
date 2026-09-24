# Post a Discord message when a watched Twitch or YouTube channel goes live.
#
# One systemd service+timer pair per configured channel (same shape as
# host-watch.nix). Each run checks the platform API, compares the result
# against a state file, and posts to Discord only on the offline->live edge —
# no "stream ended" follow-up, no double-posting while a stream stays live.
#
# YouTube: deliberately NOT search.list (100 quota units/check). A live
# stream gets a video resource in its channel's uploads playlist as soon as
# it starts, so playlistItems.list (1 unit) + videos.list (1 unit) finds it
# for 2 units/check instead — see the daily-quota assertion below.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.liveNotify;

  channelType = lib.types.submodule {
    options = {
      platform = lib.mkOption {
        type = lib.types.enum [
          "twitch"
          "youtube"
        ];
        description = "Which platform this channel lives on.";
      };
      id = lib.mkOption {
        type = lib.types.str;
        description = ''
          The platform-native identifier: a Twitch login name, or a YouTube
          channel ID (the `UC...` form — NOT an `@handle`, which would cost an
          extra lookup call to resolve).
        '';
      };
      webhookFile = lib.mkOption {
        type = lib.types.str;
        description = ''
          Path to an agenix-decrypted env file holding this channel's Discord
          webhook: `DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...`.
        '';
      };
      discordMention = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "<@&123456789012345678>";
        description = "Optional Discord mention prefixed onto the alert (a role, user, or @everyone). Not a secret, so it's plain config rather than agenix.";
      };
      intervalSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 300;
        description = ''
          Seconds between checks, via the timer's `OnUnitActiveSec`. Also
          what the YouTube quota assertion below is computed from.
        '';
      };
    };
  };

  twitchChannels = lib.filterAttrs (_: c: c.platform == "twitch") cfg.channels;
  youtubeChannels = lib.filterAttrs (_: c: c.platform == "youtube") cfg.channels;

  # 1 unit for playlistItems.list + 1 for videos.list, per check.
  youtubeUnitsPerCheck = 2;

  youtubeDailyUnits = lib.foldlAttrs (
    acc: _: c:
    acc + youtubeUnitsPerCheck * (86400 / c.intervalSeconds)
  ) 0 youtubeChannels;

  # `id` and the channel key `name` are Nix-interpolated directly into the
  # generated shell scripts below at eval time (not templated at runtime) —
  # same as host-watch's per-target scripts. `discordMention` is also
  # interpolated, but escaped via lib.escapeShellArg before embedding.
  # These assertions ensure literal embedding is safe: an id or name
  # containing `"` or `$` would otherwise corrupt the generated script.
  badIds = lib.filterAttrs (_: c: builtins.match "[A-Za-z0-9_-]+" c.id == null) cfg.channels;
  badNames = lib.filterAttrs (name: _: builtins.match "[A-Za-z0-9_-]+" name == null) cfg.channels;
  badYoutubeIds = lib.filterAttrs (_: c: !lib.hasPrefix "UC" c.id) youtubeChannels;

  mention = c: lib.escapeShellArg (if c.discordMention == null then "" else c.discordMention);

  # Every request goes through req(), which classifies curl's exit status.
  # --max-time is per attempt and the retry delay is not counted against it,
  # so one transient failure costs 30s and one more try. --retry-all-errors is
  # what makes that retry cover a DNS resolution failure at all; plain --retry
  # only covers transient HTTP statuses and a few connection errors.
  #
  # If the retry also fails, the exit status says whether this check is broken
  # or the box simply has no network: 6 (host not resolved), 7 (connect failed)
  # and 28 (timed out) are an outage, and req reports them as 75 so the caller
  # skips the run rather than paging. Anything else stays a failure — notably
  # 22, --fail on an HTTP error, i.e. a bad key or a rejected webhook.
  #
  # Retrying *through* an outage instead is not an option: these are oneshot
  # units on a per-channel intervalSeconds timer and systemd will not start a
  # run while one is active, so a unit that retried for minutes would suppress
  # its own schedule. Skipping costs at most one interval of go-live
  # latency, and because a skip exits before the state file is written, a
  # pending notification is re-detected and re-sent on the next run.
  shellPrelude = name: ''
    req() {
      local rc=0
      curl -sS --fail --max-time 20 --retry 1 --retry-delay 30 --retry-all-errors "$@" || rc=$?
      case "$rc" in
        6 | 7 | 28) return 75 ;;
        *) return "$rc" ;;
      esac
    }

    # $1 = captured exit status, $2 = what was being attempted.
    bail() {
      if [ "$1" -eq 75 ]; then
        echo "live-notify-${name}: $2: no network, skipping this check" >&2
        exit 0
      fi
      echo "live-notify-${name}: $2 failed" >&2
      exit 1
    }
  '';

  twitchScript = name: c: ''
    set -uo pipefail
    ${shellPrelude name}
    if [ -z "''${TWITCH_CLIENT_ID:-}" ] || [ -z "''${TWITCH_CLIENT_SECRET:-}" ]; then
      echo "live-notify-${name}: missing Twitch credentials (services.liveNotify.twitch.credentialsFile)" >&2
      exit 1
    fi
    if [ -z "''${DISCORD_WEBHOOK_URL:-}" ]; then
      echo "live-notify-${name}: missing Discord webhook URL" >&2
      exit 1
    fi

    rc=0
    token=$(req -X POST "https://id.twitch.tv/oauth2/token" \
      --data-urlencode "client_id=$TWITCH_CLIENT_ID" \
      --data-urlencode "client_secret=$TWITCH_CLIENT_SECRET" \
      --data-urlencode "grant_type=client_credentials" | jq -r '.access_token') || rc=$?
    if [ "$rc" -ne 0 ]; then bail "$rc" "Twitch token request"; fi
    if [ -z "$token" ] || [ "$token" = "null" ]; then
      echo "live-notify-${name}: failed to obtain a Twitch app access token" >&2
      exit 1
    fi

    rc=0
    resp=$(req \
      -H "Client-Id: $TWITCH_CLIENT_ID" \
      -H "Authorization: Bearer $token" \
      "https://api.twitch.tv/helix/streams?user_login=${c.id}") || rc=$?
    if [ "$rc" -ne 0 ]; then bail "$rc" "Twitch streams request"; fi

    count=$(echo "$resp" | jq '.data | length')
    state_file="$STATE_DIRECTORY/state"
    prev=$(cat "$state_file" 2>/dev/null || echo offline)
    if [ "$count" -gt 0 ]; then cur=live; else cur=offline; fi

    if [ "$prev" != live ] && [ "$cur" = live ]; then
      user_name=$(echo "$resp" | jq -r '.data[0].user_name')
      title=$(echo "$resp" | jq -r '.data[0].title')
      game=$(echo "$resp" | jq -r '.data[0].game_name')

      MENTION=${mention c}
      lines="🔴 **$user_name** is live on Twitch: $title"
      if [ -n "$game" ] && [ "$game" != null ]; then lines="$lines ($game)"; fi
      lines="$lines
    https://twitch.tv/${c.id}"
      if [ -n "$MENTION" ]; then lines="$MENTION
    $lines"; fi

      payload=$(jq -n --arg c "$lines" '{content: $c}')
      rc=0
      req -H "Content-Type: application/json" \
        -d "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null || rc=$?
      if [ "$rc" -ne 0 ]; then bail "$rc" "Discord webhook post"; fi
    fi

    echo "$cur" > "$state_file"
  '';

  youtubeScript = name: c: ''
    set -uo pipefail
    ${shellPrelude name}
    if [ -z "''${YOUTUBE_API_KEY:-}" ]; then
      echo "live-notify-${name}: missing YouTube API key (services.liveNotify.youtube.apiKeyFile)" >&2
      exit 1
    fi
    if [ -z "''${DISCORD_WEBHOOK_URL:-}" ]; then
      echo "live-notify-${name}: missing Discord webhook URL" >&2
      exit 1
    fi

    uploads_playlist="UU${lib.removePrefix "UC" c.id}"

    rc=0
    items=$(req \
      "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&playlistId=$uploads_playlist&maxResults=5&key=$YOUTUBE_API_KEY") || rc=$?
    if [ "$rc" -ne 0 ]; then bail "$rc" "playlistItems request"; fi

    video_ids=$(echo "$items" | jq -r '[.items[]?.snippet.resourceId.videoId] | join(",")')

    state_file="$STATE_DIRECTORY/state"
    prev=$(cat "$state_file" 2>/dev/null || echo offline)
    cur=offline
    live_json=""

    if [ -n "$video_ids" ]; then
      rc=0
      videos=$(req \
        "https://www.googleapis.com/youtube/v3/videos?part=snippet&id=$video_ids&key=$YOUTUBE_API_KEY") || rc=$?
      if [ "$rc" -ne 0 ]; then bail "$rc" "videos request"; fi
      live_json=$(echo "$videos" | jq -c '[.items[] | select(.snippet.liveBroadcastContent == "live")][0]')
      if [ "$live_json" != null ] && [ -n "$live_json" ]; then
        cur=live
      fi
    fi

    if [ "$prev" != live ] && [ "$cur" = live ]; then
      video_id=$(echo "$live_json" | jq -r '.id')
      title=$(echo "$live_json" | jq -r '.snippet.title')
      channel_title=$(echo "$live_json" | jq -r '.snippet.channelTitle')

      MENTION=${mention c}
      lines="🔴 **$channel_title** is live on YouTube: $title
    https://youtu.be/$video_id"
      if [ -n "$MENTION" ]; then lines="$MENTION
    $lines"; fi

      payload=$(jq -n --arg c "$lines" '{content: $c}')
      rc=0
      req -H "Content-Type: application/json" \
        -d "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null || rc=$?
      if [ "$rc" -ne 0 ]; then bail "$rc" "Discord webhook post"; fi
    fi

    echo "$cur" > "$state_file"
  '';

  mkChannelService = name: c: {
    description = "Check ${name} (${c.platform}) for going live, notify Discord";
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "live-notify-${name}";
      EnvironmentFile = [
        (if c.platform == "twitch" then cfg.twitch.credentialsFile else cfg.youtube.apiKeyFile)
        c.webhookFile
      ];
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
    path = [
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    script = if c.platform == "twitch" then twitchScript name c else youtubeScript name c;
  };

  mkChannelTimer = name: c: {
    description = "Periodic live-check for ${name}";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # OnBootSec kicks off the first run; OnUnitActiveSec repeats it from
      # there. OnUnitActiveSec alone never fires a first run, since it is
      # relative to when the service last ran.
      OnBootSec = "1m";
      OnUnitActiveSec = "${toString c.intervalSeconds}s";
      Persistent = false;
      RandomizedDelaySec = "10s";
    };
  };
in
{
  options.services.liveNotify = {
    enable = lib.mkEnableOption "Discord alerts when a watched Twitch/YouTube channel goes live";

    twitch.credentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Env file with `TWITCH_CLIENT_ID=` and `TWITCH_CLIENT_SECRET=`, used
        to mint a client-credentials app access token on every check.
        Required if any channel has `platform = "twitch"`.
      '';
    };

    youtube = {
      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Env file with `YOUTUBE_API_KEY=`. Required if any channel has
          `platform = "youtube"`.
        '';
      };

      dailyQuotaBudget = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10000;
        description = ''
          Daily YouTube Data API quota budget, in units — 10000 is the
          standard default per project. Checked at eval time against what the
          configured YouTube channels' `intervalSeconds` would actually use,
          at 2 units/check (playlistItems.list + videos.list).
        '';
      };
    };

    channels = lib.mkOption {
      type = lib.types.attrsOf channelType;
      default = { };
      description = "Channels to watch, keyed by a short name used in the unit name.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = youtubeDailyUnits <= cfg.youtube.dailyQuotaBudget;
        message = "liveNotify: configured YouTube channel(s) would use ${toString youtubeDailyUnits} quota units/day, over the ${toString cfg.youtube.dailyQuotaBudget}-unit budget (services.liveNotify.youtube.dailyQuotaBudget) — raise the budget, lengthen intervalSeconds, or drop a channel.";
      }
      {
        assertion = youtubeChannels == { } || cfg.youtube.apiKeyFile != null;
        message = "liveNotify: YouTube channel(s) configured but services.liveNotify.youtube.apiKeyFile is not set";
      }
      {
        assertion = twitchChannels == { } || cfg.twitch.credentialsFile != null;
        message = "liveNotify: Twitch channel(s) configured but services.liveNotify.twitch.credentialsFile is not set";
      }
      {
        assertion = badIds == { };
        message =
          "liveNotify: channel id(s) must match [A-Za-z0-9_-]+ (embedded literally into generated scripts/URLs): "
          + lib.concatStringsSep ", " (lib.attrNames badIds);
      }
      {
        assertion = badNames == { };
        message =
          "liveNotify: channel name(s) (keys) must match [A-Za-z0-9_-]+ (embedded literally into generated scripts): "
          + lib.concatStringsSep ", " (lib.attrNames badNames);
      }
      {
        assertion = badYoutubeIds == { };
        message =
          "liveNotify: YouTube channel id(s) must be the UC... channel ID, not an @handle: "
          + lib.concatStringsSep ", " (lib.attrNames badYoutubeIds);
      }
    ];

    systemd.services = lib.mapAttrs' (
      name: c: lib.nameValuePair "live-notify-${name}" (mkChannelService name c)
    ) cfg.channels;
    systemd.timers = lib.mapAttrs' (
      name: c: lib.nameValuePair "live-notify-${name}" (mkChannelTimer name c)
    ) cfg.channels;

    services.notifyFailure.units = map (n: "live-notify-${n}.service") (lib.attrNames cfg.channels);
  };
}
