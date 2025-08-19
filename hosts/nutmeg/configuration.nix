# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  pkgs,
  pkgs-unstable,
  ...
}: {
  imports = [
    ./adguard.nix
    ./audit.nix
    ./hardware-configuration.nix
    ./home-assistant.nix
    ./plex.nix
    ./tailscale.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nutmeg"; # Define your hostname.

  # Basic security
  security.sudo.execWheelOnly = true;

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable man pages
  documentation = {
    dev.enable = true;
    man.generateCaches = true;
    nixos.includeAllModules = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.defaultUserShell = pkgs.fish;
  users.users.natsume = {
    isNormalUser = true;
    description = "Natsume";
    extraGroups = ["wheel"];
    shell = pkgs.fish;
    packages = [
      pkgs-unstable.ghostty.terminfo
      pkgs.nix-output-monitor
      pkgs.du-dust
      pkgs-unstable.neovim
      pkgs.lsof
      pkgs-unstable.lnav
      pkgs-unstable.helix
      pkgs.freeze # code screenshot
      pkgs.delta
      pkgs.htmlq
      pkgs.graphviz
      pkgs.shellcheck
      pkgs.gron
      pkgs.rlwrap
      pkgs.dogdns
      pkgs.git
      pkgs.rtx
      pkgs.tree
      pkgs.broot
      pkgs.yq
      pkgs.gh
      pkgs.dive
      pkgs-unstable.lazygit
      pkgs.lazydocker
      pkgs.rustup
      pkgs.nushell
      pkgs.glab
      pkgs.zoxide
      pkgs.hyperfine
      pkgs.tmux
      pkgs.ripgrep
      pkgs.unzip
      pkgs.fd
      pkgs.htop
      pkgs.jq
      pkgs.xh
      pkgs.watch
      pkgs.pv
      pkgs.bat
      pkgs.tokei
      pkgs.soupault
      pkgs-unstable.bottom
      pkgs.wget
      pkgs.certbot
      pkgs.packwiz # for meloncraft-modpack
      pkgs-unstable.uv # for python
      pkgs-unstable.mise
      pkgs-unstable.jujutsu
      pkgs-unstable.jjui
    ];
  };

  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    man-pages # enable man pages
    vim
    fish
    fishPlugins.pure
    sqlite
    sqlite-interactive
    isd # TUI to work with systemd units
  ];

  # fileSystems."/mnt/reddit" = {
  #   device = "192.168.1.194:/volume1/project-reddit-data";
  #   fsType = "nfs";
  #   options = [
  #     "nfsvers=4.2"
  #     "noatime"
  #     "x-systemd.automount"
  #     "noauto"
  #     "x-systemd.idle-timeout=60"
  #     "x-systemd.device-timeout=5s"
  #     "x-systemd.mount-timeout=5s"
  #   ];
  # };

  # fileSystems."/mnt/stories" = {
  #   device = "192.168.1.194:/volume1/project-story-archive";
  #   fsType = "nfs";
  #   options = [
  #     "nfsvers=4.1"
  #     "noatime"
  #     "x-systemd.automount"
  #     "noauto"
  #     "x-systemd.idle-timeout=60"
  #     "x-systemd.device-timeout=5s"
  #     "x-systemd.mount-timeout=5s"
  #   ];
  # };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.fish.enable = true;
  # programs.mosh.enable = true;

  # List services that you want to enable:
  services.openssh.enable = true;
  services.openssh.extraConfig = ''
    AcceptEnv COLORTERM
  '';

  virtualisation.oci-containers.backend = "podman";
  virtualisation.podman.enable = true;
  # periodically prune Podman resources
  virtualisation.podman.autoPrune.enable = true;
  # Create a `docker` alias for podman, to use it as a drop-in replacement
  virtualisation.podman.dockerCompat = true;
  # Required for containers under podman-compose to be able to talk to each other.
  # virtualisation.podman.defaultNetwork.settings.dns_enabled = true;

  # Open ports in the firewall.
  networking.nftables.enable = true;
  networking.firewall.enable = true;

  networking.firewall.allowedTCPPorts = [
    22
    80
    443
  ];

  # power management for lower idle power draw
  powerManagement.powertop.enable = true;

  # system.autoUpgrade = {
  #   enable = false;
  #   allowReboot = true;
  #   persistent = true;
  #   randomizedDelaySec = "5min";
  #   rebootWindow = { lower = "01:00"; upper = "06:00"; };
  # };

  # nix.gc = {
  #   automatic = true;
  #   randomizedDelaySec = "14m";
  #   options = "--delete-older-than 10d";
  # };

  services.veilid = {
    enable = true;
    openFirewall = true;
  };

  programs.nh.flake = "/home/natsume/nix-config#nutmeg";

  services.freeradius = {
    enable = true;
    debug = true;
    # Define a user for the client to connect with
    configDir = pkgs.writeTextDir "users" ''
      testuser Cleartext-Password := "testpassword"
    '';
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
