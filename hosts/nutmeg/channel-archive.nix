# yt-dlp channel archives on nutmeg.
# - ditherdown: Twitch VODs (Phase 1).
# - 6 YouTube channels migrated off pinchflat (Phase 2).
# Per-channel `enable` defaults to false (module-wide), so every active channel
# sets `enable = true`. Staged/backlog channels can be added with enable=false.
{ ... }:
{
  services.channelArchive = {
    enable = true;
    channels.ditherdown = {
      enable = true;
      url = "https://www.twitch.tv/ditherdown/videos?filter=archives&sort=time";
    };
    channels."settei-seven" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCedsCHD4XKPg5YiK56jTypg/videos";
      destination = "/mnt/channels/Settei Seven";
      rateLimit = true;
    };
    channels."axell-the-swampert" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCzd7kTq1TCKOA6kPWaW2Z8Q/videos";
      destination = "/mnt/channels/Axell The Swampert";
      rateLimit = true;
    };
    channels."jen" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCjQSQVa1-OgDmp4ypfdRbWQ/videos";
      destination = "/mnt/channels/jen";
      rateLimit = true;
    };
    channels."adrisaurus" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCAHPCNxU4A-TUV-lnu7u4tA/videos";
      destination = "/mnt/channels/adrisaurus";
      rateLimit = true;
    };
    channels."displaced-gamers" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCWoSKWs8h6lFdiEDAjuIfpA/videos";
      destination = "/mnt/channels/Displaced Gamers";
      rateLimit = true;
    };
    channels."caitlin-myers" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCDzdRLILLWlHxXnj3HhXW0A/videos";
      destination = "/mnt/channels/Caitlin Myers";
      rateLimit = true;
    };
  };
}
