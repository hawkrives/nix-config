{ config, ... }:
{
  # YouTube Data API key, Twitch app credentials, and each channel's own
  # Discord webhook. Two channels share a webhook with a sibling channel on
  # the other platform (same streamer, one Discord destination) — see the
  # comments below on kumaNeNeYoutube and takumiMkIITwitch.
  age.secrets.youtube-notify.file = ../../secrets/youtube-notify.age;
  age.secrets.twitch-notify.file = ../../secrets/twitch-notify.age;
  age.secrets."live-notify-takumiMkII".file = ../../secrets/live-notify-takumiMkII.age;
  age.secrets."live-notify-kuinanoyumemi".file = ../../secrets/live-notify-kuinanoyumemi.age;
  age.secrets."live-notify-arusan0117".file = ../../secrets/live-notify-arusan0117.age;
  age.secrets."live-notify-honkenhawk".file = ../../secrets/live-notify-honkenhawk.age;
  age.secrets."live-notify-kuma-ne-ne".file = ../../secrets/live-notify-kuma-ne-ne.age;
  age.secrets."live-notify-alphaomegaentmt".file = ../../secrets/live-notify-alphaomegaentmt.age;
  age.secrets."live-notify-grys0l".file = ../../secrets/live-notify-grys0l.age;
  age.secrets."live-notify-ditherdown".file = ../../secrets/live-notify-ditherdown.age;

  services.liveNotify = {
    enable = true;

    youtube.apiKeyFile = config.age.secrets.youtube-notify.path;
    twitch.credentialsFile = config.age.secrets.twitch-notify.path;

    channels.takumiMkII = {
      platform = "youtube";
      id = "UCisGyQZ4M9fbi2_x5PoaHRg"; # youtube.com/@TakumiMk-II
      webhookFile = config.age.secrets."live-notify-takumiMkII".path;
    };

    # Same streamer as takumiMkII above, on Twitch — reuses that channel's
    # webhook so both platforms post to the same Discord channel.
    channels.takumiMkIITwitch = {
      platform = "twitch";
      id = "takumimk2"; # twitch.tv/takumimk2
      webhookFile = config.age.secrets."live-notify-takumiMkII".path;
    };

    channels.kuinanoyumemi = {
      platform = "twitch";
      id = "kuinanoyumemi"; # twitch.tv/kuinanoyumemi
      webhookFile = config.age.secrets."live-notify-kuinanoyumemi".path;
    };

    channels.arusan0117 = {
      platform = "twitch";
      id = "arusan0117"; # twitch.tv/arusan0117
      webhookFile = config.age.secrets."live-notify-arusan0117".path;
    };

    channels.honkenhawk = {
      platform = "twitch";
      id = "honkenhawk"; # twitch.tv/honkenhawk
      webhookFile = config.age.secrets."live-notify-honkenhawk".path;
    };

    channels.kumaNeNeTwitch = {
      platform = "twitch";
      id = "kuma_ne_ne"; # twitch.tv/kuma_ne_ne
      webhookFile = config.age.secrets."live-notify-kuma-ne-ne".path;
    };

    # Same streamer as kumaNeNeTwitch above, on YouTube — reuses that
    # channel's webhook so both platforms post to the same Discord channel.
    channels.kumaNeNeYoutube = {
      platform = "youtube";
      id = "UCii-O52_aeoxH0GpEdf3low"; # youtube.com/@kuma.ne-ne
      webhookFile = config.age.secrets."live-notify-kuma-ne-ne".path;
    };

    channels.alphaomegaentmt = {
      platform = "twitch";
      id = "alphaomegaentmt"; # twitch.tv/alphaomegaentmt
      webhookFile = config.age.secrets."live-notify-alphaomegaentmt".path;
    };

    channels.grys0l = {
      platform = "twitch";
      id = "grys0l"; # twitch.tv/grys0l
      webhookFile = config.age.secrets."live-notify-grys0l".path;
    };

    channels.ditherdown = {
      platform = "twitch";
      id = "ditherdown"; # twitch.tv/ditherdown
      webhookFile = config.age.secrets."live-notify-ditherdown".path;
    };
  };
}
