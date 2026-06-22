{ synologyMount, ... }:
{
  fileSystems."/mnt/music" = synologyMount "/volume1/media-music" { };
  fileSystems."/mnt/movies" = synologyMount "/volume1/media-movies" { };
  fileSystems."/mnt/shows" = synologyMount "/volume1/media-shows" { };

  # Old qBittorrent download staging (jp-show / anime / unsorted / games torrents
  # seed from here, plus partial downloads). Mounted so the migrated torrents can
  # find their data.
  fileSystems."/mnt/downloads" = synologyMount "/volume1/downloads" { };

  fileSystems."/mnt/library" = synologyMount "/volume1/library" { };
}
