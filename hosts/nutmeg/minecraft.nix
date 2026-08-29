{
  lib,
  pkgs,
  ...
}: let
  modpack = pkgs.fetchPackwizModpack {
    url = "https://raw.githubusercontent.com/hawkrives/meloncraft-modpack/b1f2671d87bfbf13d96894c8ea10297f971349dd/pack.toml";
    packHash = "sha256-vAE5sRCBoMcOT2zlEca48v7UmSCcfIzCnaFavELo+z0=";
    # Without this, `modpack.manifest` below falls back to importTOML on
    # "${drv}/pack.toml" — an import-from-derivation, which forces the whole
    # modpack to be fetched and built before evaluation of this host can even
    # continue. It costs nothing today only because `enable = false` keeps
    # serverVersion unforced; flipping the service back on would reintroduce it.
    # manifestHash makes the manifest a plain fetchurl of pack.toml instead.
    manifestHash = "sha256-UN9RmkFjuaK38aN7AQd5ZEQ8Cgcn9SA5HSsggaK8F+o=";
  };
  mcVersion = modpack.manifest.versions.minecraft;
  serverVersion = lib.replaceStrings ["."] ["_"] "vanilla-${mcVersion}";
in {
  services.minecraft-servers = {
    enable = false;

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
