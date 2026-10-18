# Watch vids_by_melon's Twitch stream from both ends — OBS on the streaming
# Mac (obs-websocket), the HLS feed viewers get, and this house's route to
# Twitch's ingest — and tell Telegram where frame drops came from. See the
# docstring in ./stream-watch.py for what each probe measures.
#
# Idle whenever OBS is closed or the Mac is asleep: it retries the websocket
# every 30s and only probes Twitch while OBS reports an active stream.
{
  config,
  pkgs,
  ...
}: let
  python = pkgs.python3.withPackages (p: [p.websockets]);
in {
  systemd.services.stream-watch = {
    description = "Attribute vids_by_melon's Twitch frame drops (OBS / network / Twitch)";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];
    path = [
      pkgs.streamlink
      pkgs.ffmpeg-headless
    ];
    environment = {
      # The Mac's address on the LAN; obs-websocket's default port.
      OBS_URL = "ws://192.168.1.179:4455";
      TWITCH_LOGIN = "vids_by_melon";
      # streamlink keeps a small cache under $HOME.
      HOME = "/var/lib/stream-watch";
    };
    # Crash-looping, rather than one transient restart, is what reaches
    # `failed` and so notify-failure.
    startLimitIntervalSec = 600;
    startLimitBurst = 5;
    serviceConfig = {
      ExecStart = "${python.interpreter} -I ${./stream-watch.py}";
      # TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID, shared with notify-failure.
      EnvironmentFile = config.age.secrets.telegram-notify.path;
      Restart = "always";
      RestartSec = 30;
      DynamicUser = true;
      StateDirectory = "stream-watch";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
    };
  };

  services.notifyFailure.units = ["stream-watch.service"];
}
