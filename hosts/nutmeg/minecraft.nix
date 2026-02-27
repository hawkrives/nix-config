{ lib, pkgs, ... }:
let
  modpack = pkgs.fetchPackwizModpack {
    url = "https://raw.githubusercontent.com/hawkrives/meloncraft-modpack/b1f2671d87bfbf13d96894c8ea10297f971349dd/pack.toml";
    packHash = "sha256-vAE5sRCBoMcOT2zlEca48v7UmSCcfIzCnaFavELo+z0=";
  };
  mcVersion = modpack.manifest.versions.minecraft;
  serverVersion = lib.replaceStrings [ "." ] [ "_" ] "vanilla-${mcVersion}";
in
{
  services.minecraft-servers = {
    enable = true;
    eula = true;
    openFirewall = true;
  };

  services.minecraft-servers.servers.meloncraft = {
    enable = true;
    autoStart = true;

    serverProperties = {
      motd = "hello shintaro!";
      enable-rcon = true;
    };

    package = pkgs.vanillaServers.${serverVersion};
    symlinks = {
      "mods" = "${modpack}/mods";
      "modpack" = "${modpack}";
    };
  };
}
