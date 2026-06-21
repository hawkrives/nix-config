{ synologyMount, ... }:
{
  fileSystems."/mnt/music" = synologyMount "/volume1/media-music" { };
  fileSystems."/mnt/movies" = synologyMount "/volume1/media-movies" { };
  fileSystems."/mnt/shows" = synologyMount "/volume1/media-shows" { };
}
