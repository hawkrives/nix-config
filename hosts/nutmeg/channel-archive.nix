# yt-dlp channel archives on nutmeg. Phase 1: the ditherdown Twitch VODs
# (reuses the pre-seeded /mnt/channels/ditherdown/archive.txt). YouTube channels
# (migrated off pinchflat) come in a later phase.
{ ... }:
{
  services.channelArchive = {
    enable = true;
    channels.ditherdown = {
      url = "https://www.twitch.tv/ditherdown/videos?filter=archives&sort=time";
    };
    channels."settei-seven" = {
      url = "https://www.youtube.com/channel/UCedsCHD4XKPg5YiK56jTypg/videos";
      destination = "/mnt/channels/Settei Seven";
      rateLimit = true;
    };
    channels."axell-the-swampert" = {
      url = "https://www.youtube.com/channel/UCzd7kTq1TCKOA6kPWaW2Z8Q/videos";
      destination = "/mnt/channels/Axell The Swampert";
      rateLimit = true;
    };
    channels."jen" = {
      url = "https://www.youtube.com/channel/UCjQSQVa1-OgDmp4ypfdRbWQ/videos";
      destination = "/mnt/channels/jen";
      rateLimit = true;
    };
    channels."adrisaurus" = {
      url = "https://www.youtube.com/channel/UCAHPCNxU4A-TUV-lnu7u4tA/videos";
      destination = "/mnt/channels/adrisaurus";
      rateLimit = true;
    };
    channels."displaced-gamers" = {
      url = "https://www.youtube.com/channel/UCWoSKWs8h6lFdiEDAjuIfpA/videos";
      destination = "/mnt/channels/Displaced Gamers";
      rateLimit = true;
    };
    channels."caitlin-myers" = {
      url = "https://www.youtube.com/channel/UCDzdRLILLWlHxXnj3HhXW0A/videos";
      destination = "/mnt/channels/Caitlin Myers";
      rateLimit = true;
    };
  };
}
