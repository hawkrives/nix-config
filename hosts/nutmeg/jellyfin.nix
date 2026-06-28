{ pkgs, ... }:
{
  services.jellyfin.enable = true;

  # The jellyfin module has no port/openFirewall options; HTTP is 8096, set in
  # Jellyfin's own network.xml. Open it for the LAN (merges with the other
  # allowedTCPPorts on this host); the tailnet goes through tsnsrv below.
  networking.firewall.allowedTCPPorts = [ 8096 ];

  # "users" (gid 100) for read access to the NAS media tree, reached via the
  # /mnt shares declared in servarr.nix. render/video for the Haswell iGPU.
  users.users.jellyfin.extraGroups = [ "users" "render" "video" ];

  # System VAAPI driver for the 2014 Mac Mini's Haswell iGPU (Gen7.5 -> i965).
  # Plex HW-transcodes with its own bundled libs, but Jellyfin uses the system
  # driver, so it has to be present. Enable VAAPI in Jellyfin's Playback UI
  # (device /dev/dri/renderD128); i965 is the only Intel driver, so it auto-picks.
  hardware.graphics = {
    enable = true;
    extraPackages = [ pkgs.intel-vaapi-driver ];
  };

  # Expose on the tailnet: https://fin.<tailnet>.ts.net -> 127.0.0.1:8096.
  # 127.0.0.1 (not the "localhost" default) avoids resolving to ::1 first.
  services.tsnsrv.services.fin.urlParts = {
    host = "127.0.0.1";
    port = 8096;
  };
}
