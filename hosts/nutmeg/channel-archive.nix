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
  };
}
