{
  flake,
  hostName,
  pkgs,
  ...
}: {
  imports = [
    flake.modules.common.nixpkgs-unstable # provides the pkgsUnstable argument to other modules

    flake.nixosModules.host-shared
    flake.nixosModules.host-server
    flake.nixosModules.host-nixos
    flake.nixosModules.veilid-shared

    # configuration
    ./hardware.nix

    # modules
    ./adguard.nix
    ./home-assistant.nix
    ./home-assistant-matter.nix
    ./plex.nix
    ./tailscale.nix
    ./syncthing.nix
    ./paperless.nix
    ./nix-serve.nix
    ./peertube.nix
    ./discourse.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = hostName; # hostName is detected by Blueprint; defaults to the containing folder's name

  services.mbpfan.enable = true; # enable Mac fan control daemon
  systemd.coredump.enable = false; # disable core dumps

  users.users.natsume = {
    isNormalUser = true;
    description = "Natsume";
    extraGroups = ["wheel"];
    shell = pkgs.fish;
  };

  programs.nh.flake = "/home/natsume/nix-config#nutmeg";
  programs.nh.clean = {
    enable = true;
    dates = "weekly";
    extraArgs = "--keep-since 4d --keep 3";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
