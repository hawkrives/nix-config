{ config, ... }:
{
  # YouTube Data API key (services.liveNotify.youtube.apiKeyFile) and this
  # channel's Discord webhook. No Twitch credentials yet — nothing below has
  # platform = "twitch"; add a twitch-notify.age secret and
  # services.liveNotify.twitch.credentialsFile when a Twitch channel is added.
  age.secrets.youtube-notify.file = ../../secrets/youtube-notify.age;
  age.secrets."live-notify-takumiMkII".file = ../../secrets/live-notify-takumiMkII.age;

  services.liveNotify = {
    enable = true;

    youtube.apiKeyFile = config.age.secrets.youtube-notify.path;

    channels.takumiMkII = {
      platform = "youtube";
      id = "UCisGyQZ4M9fbi2_x5PoaHRg"; # youtube.com/@TakumiMk-II
      webhookFile = config.age.secrets."live-notify-takumiMkII".path;
    };
  };
}
