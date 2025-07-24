{
  username,
  hostname,
  nextdnsProfile,
}:
{ config, pkgs, ... }:
{
  imports = [ ../../common/hosts/darwin.nix ];

  nix.settings.trusted-users = [
    "root"
    username
  ];

  networking.hostName = hostname;
  networking.computerName = hostname;

  system.defaults = {
    dock.autohide = true;
    dock.mru-spaces = false;
    smb.NetBIOSName = hostname;
    screencapture.location = "~/Pictures/screenshots";
  };

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    shell = pkgs.bashInteractive;
  };
}
