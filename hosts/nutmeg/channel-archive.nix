# yt-dlp channel archives on nutmeg, organized into top-level buckets under
# /mnt/channels (streams/music/gaming/videos/learning/settei/... — for Plex
# library scanning). Per-channel `enable` defaults false (module-wide); active
# channels set enable=true. Staged backlog lives in channel-archive-backlog.nix.
{ ... }:
{
  services.channelArchive = {
    enable = true;
    channels.ditherdown = {
      enable = true;
      url = "https://www.twitch.tv/ditherdown/videos?filter=archives&sort=time";
      destination = "/mnt/channels/streams/ditherdown";
    };
    channels."settei-seven" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCedsCHD4XKPg5YiK56jTypg/videos";
      destination = "/mnt/channels/settei/Settei Seven";
      rateLimit = true;
    };
    channels."axell-the-swampert" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCzd7kTq1TCKOA6kPWaW2Z8Q/videos";
      destination = "/mnt/channels/music/Axell The Swampert";
      rateLimit = true;
    };
    channels."jen" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCjQSQVa1-OgDmp4ypfdRbWQ/videos";
      destination = "/mnt/channels/music/jen";
      rateLimit = true;
    };
    channels."adrisaurus" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCAHPCNxU4A-TUV-lnu7u4tA/videos";
      destination = "/mnt/channels/music/adrisaurus";
      rateLimit = true;
    };
    channels."displaced-gamers" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCWoSKWs8h6lFdiEDAjuIfpA/videos";
      destination = "/mnt/channels/learning/Displaced Gamers";
      rateLimit = true;
    };
    channels."caitlin-myers" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCDzdRLILLWlHxXnj3HhXW0A/videos";
      destination = "/mnt/channels/music/Caitlin Myers";
      rateLimit = true;
    };
  };
}
