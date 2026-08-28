# yt-dlp channel archives on nutmeg, organized into top-level buckets under
# /mnt/channels (streams/music/gaming/videos/learning/settei/... — for Plex
# library scanning). Per-channel `enable` defaults false (module-wide); active
# channels set enable=true. Staged backlog lives in channel-archive-backlog.nix.
{ config, pkgs, ... }:
{
  age.secrets.plex-token.file = ../../secrets/plex-token.age;

  # Reads the local mbox mail channelArchive.alertUser delivers to
  # /var/mail/natsume on non-403/429 failures — no MTA involved, just a
  # reader for the mbox file the service appends to directly.
  environment.systemPackages = [ pkgs.mailutils ];

  services.channelArchive = {
    enable = true;
    plexUrl = "http://localhost:32400";
    plexSection = "37";
    plexTokenFile = config.age.secrets.plex-token.path;
    alertUser = "natsume";

    channels."arusan0117" = {
      enable = true;
      incremental = true;
      ignoreErrors = false;
      includeLive = true;
      url = "https://www.twitch.tv/arusan0117/videos?filter=archives&sort=time";
      destination = "/mnt/channels/videos/arusan0117";
      restructure = true;
    };
    channels."kuma_ne_ne" = {
      enable = true;
      incremental = true;
      ignoreErrors = false;
      includeLive = true;
      url = "https://www.twitch.tv/kuma_ne_ne/videos?filter=archives&sort=time";
      destination = "/mnt/channels/videos/kuma_ne_ne";
      restructure = true;
    };
    channels."kume_ne_ne_yt" = {
      enable = true;
      incremental = true;
      ignoreErrors = false;
      includeLive = true;
      url = "https://youtube.com/@kuma.ne-ne";
      destination = "/mnt/channels/videos/kuma_ne_ne";
      restructure = true;
    };
    channels."midnightsumo" = {
      enable = true;
      incremental = true;
      ignoreErrors = false;
      includeLive = true;
      url = "https://www.twitch.tv/MidnightSumo/videos?sort=time";
      destination = "/mnt/channels/videos/midnightsumo";
      restructure = true;
    };
    channels."ditherdown" = {
      enable = true;
      incremental = true;
      ignoreErrors = false;
      includeLive = true;
      url = "https://www.twitch.tv/ditherdown/videos?filter=archives&sort=time";
      destination = "/mnt/channels/videos/ditherdown";
      restructure = true;
    };
    channels."ditherdown-clips" = {
      enable = true;
      incremental = true;
      ignoreErrors = true;
      url = "https://www.twitch.tv/ditherdown/clips?filter=clips&range=all";
      # Clips land in the SAME folder as the VODs (shared archive.txt dedups by
      # id; the two units fire at randomized offsets so they don't race). Clips
      # are represented as Specials (Season 00) in the DitherDown show.
      destination = "/mnt/channels/videos/ditherdown";
      restructure = true;
    };
    channels."settei-seven" = {
      enable = true;
      incremental = true;
      ignoreErrors = false;
      url = "https://www.youtube.com/channel/UCedsCHD4XKPg5YiK56jTypg/videos";
      destination = "/mnt/channels/videos/Settei Seven";
      rateLimit = true;
      restructure = true;
    };
    channels."axell-the-swampert" = {
      enable = false;
      incremental = false;
      ignoreErrors = false;
      url = "https://www.youtube.com/channel/UCzd7kTq1TCKOA6kPWaW2Z8Q/videos";
      destination = "/mnt/channels/music/Axell The Swampert";
      rateLimit = true;
    };
    channels."jen" = {
      enable = false;
      incremental = false;
      ignoreErrors = false;
      url = "https://www.youtube.com/channel/UCjQSQVa1-OgDmp4ypfdRbWQ/videos";
      destination = "/mnt/channels/music/jen";
      rateLimit = true;
    };
    channels."adrisaurus" = {
      enable = false;
      incremental = false;
      ignoreErrors = false;
      url = "https://www.youtube.com/channel/UCAHPCNxU4A-TUV-lnu7u4tA/videos";
      destination = "/mnt/channels/music/adrisaurus";
      rateLimit = true;
    };
    channels."displaced-gamers" = {
      enable = true;
      incremental = true;
      ignoreErrors = false;
      url = "https://www.youtube.com/channel/UCWoSKWs8h6lFdiEDAjuIfpA/videos";
      destination = "/mnt/channels/videos/Displaced Gamers";
      rateLimit = true;
      restructure = true;
    };
    channels."caitlin-myers" = {
      enable = false;
      incremental = false;
      ignoreErrors = false;
      url = "https://www.youtube.com/channel/UCDzdRLILLWlHxXnj3HhXW0A/videos";
      destination = "/mnt/channels/music/Caitlin Myers";
      rateLimit = true;
    };
    channels."mia-asano" = {
      enable = false;
      incremental = false;
      ignoreErrors = false;
      url = "https://www.youtube.com/channel/UCn6Uk8gAGP4duP9HFCenj5g/videos";
      destination = "/mnt/channels/music/Mia Asano";
      rateLimit = true;
    };
  };
}
