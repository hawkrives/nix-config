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
      destination = "/mnt/channels/videos/ditherdown";
    };
    channels."ditherdown-clips" = {
      enable = true;
      # range=all is required — the default /clips view is "Top 7 Days" and
      # returns nothing; filter=clips&range=all enumerates the full back catalog.
      url = "https://www.twitch.tv/ditherdown/clips?filter=clips&range=all";
      # Clips land in the SAME folder as the VODs (shared archive.txt dedups by
      # id; the two units fire at randomized offsets so they don't race). Clips
      # are represented as Specials (Season 00) in the DitherDown show.
      destination = "/mnt/channels/videos/ditherdown";
    };
    channels."settei-seven" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCedsCHD4XKPg5YiK56jTypg/videos";
      destination = "/mnt/channels/videos/Settei Seven";
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
      destination = "/mnt/channels/videos/Displaced Gamers";
      rateLimit = true;
    };
    channels."caitlin-myers" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCDzdRLILLWlHxXnj3HhXW0A/videos";
      destination = "/mnt/channels/music/Caitlin Myers";
      rateLimit = true;
    };
    channels."mia-asano" = {
      enable = true;
      url = "https://www.youtube.com/channel/UCn6Uk8gAGP4duP9HFCenj5g/videos";
      destination = "/mnt/channels/music/Mia Asano";
      rateLimit = true;
    };
  };
}
