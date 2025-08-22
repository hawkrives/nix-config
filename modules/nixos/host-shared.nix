{pkgs, ...}: {
  # programs.vim.enable = true;

  # Accept agreements for unfree software
  nixpkgs.config.allowUnfree = true;

  # you can check if host is darwin by using pkgs.stdenv.isDarwin
  environment.systemPackages =
    [
      pkgs.btop
      pkgs.man-pages # enable man pages
    ]
    ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [pkgs.xbar]);

  # Enable man pages
  documentation.dev.enable = true;
  documentation.man.generateCaches = true;
  documentation.nixos.includeAllModules = true;

  # enable the nice nh tool on nixos systems
  programs.nh.enable = pkgs.stdenv.isLinux;
  programs.nh.clean = {
    enable = pkgs.stdenv.isLinux;
    dates = "weekly";
    extraArgs = "--keep-since 4d --keep 3";
  };

  # give me fish everywhere
  programs.fish.enable = true;

  # some basic nix settings
  nix.settings = {
    # symlink identical paths in the store in the background
    # TODO: does lix support?
    auto-optimise-store = true;
    # enable flakes and the nice cli
    experimental-features = ["nix-command" "flakes"];
    # todo put the issue link here
    secret-key-files = "/etc/nix/private-key";
    # TODO I used to have this - needed?
    # allowed-users = ["root" "natsume"];

    # support pulling things from lix and flakehub
    extra-substituters = [
      "https://cache.lix.systems"
      "https://cache.flakehub.com"
    ];
    extra-trusted-public-keys =
      [
        "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
        # TODO: am I missing a key for flakehub?
      ]
      # plus my hosts
      ++ [
        "nutmeg:6F0E+NkIvpTI0d4QSvrDb3+LYhrQwXkYjqgI9etpuEw="
        "potato-bunny:i8Ab1IPNDKp9EWfmFDZIvMm70c+D435UlIsVFhJO3ts="
      ];
  };

  virtualisation.oci-containers.backend = "podman";
  virtualisation.podman.enable = true;
  # periodically prune Podman resources
  virtualisation.podman.autoPrune.enable = true;
  # Create a `docker` alias for podman, to use it as a drop-in replacement
  virtualisation.podman.dockerCompat = true;
  # Required for containers under podman-compose to be able to talk to each other.
  # virtualisation.podman.defaultNetwork.settings.dns_enabled = true;

  # TODO: does this work now? on linux?
  # system.autoUpgrade = {
  #   enable = false; # pkgs.stdenv.isLinux
  #   allowReboot = true;
  #   persistent = true;
  #   randomizedDelaySec = "5min";
  #   rebootWindow = { lower = "01:00"; upper = "06:00"; };
  # };

  # TODO: does this work now? on linux?
  # nix.gc = {
  #   automatic = true;
  #   randomizedDelaySec = "14m";
  #   options = "--delete-older-than 10d";
  # };
}
