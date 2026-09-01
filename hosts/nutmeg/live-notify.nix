{ config, ... }:
{
  # YouTube Data API key, Twitch app credentials, and each channel's own
  # Discord webhook.
  age.secrets.youtube-notify.file = ../../secrets/youtube-notify.age;
  age.secrets.twitch-notify.file = ../../secrets/twitch-notify.age;
  age.secrets."live-notify-takumiMkII".file = ../../secrets/live-notify-takumiMkII.age;
  age.secrets."live-notify-kuinanoyumemi".file = ../../secrets/live-notify-kuinanoyumemi.age;

  services.liveNotify = {
    enable = true;

    youtube.apiKeyFile = config.age.secrets.youtube-notify.path;
    twitch.credentialsFile = config.age.secrets.twitch-notify.path;

    channels.takumiMkII = {
      platform = "youtube";
      id = "UCisGyQZ4M9fbi2_x5PoaHRg"; # youtube.com/@TakumiMk-II
      webhookFile = config.age.secrets."live-notify-takumiMkII".path;
    };

    channels.kuinanoyumemi = {
      platform = "twitch";
      id = "kuinanoyumemi"; # twitch.tv/kuinanoyumemi
      webhookFile = config.age.secrets."live-notify-kuinanoyumemi".path;
    };
  };
}
