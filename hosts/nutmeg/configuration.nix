# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, inputs, tsnsrv, ... }:

{
  imports =
    [
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
  environment.systemPackages = [ pkgs.man-pages ];
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
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;
    packages = with pkgs; [
      nix-output-monitor
      du-dust
      neovim
      lsof
      lnav
      helix
      freeze # code screenshot
      # visidata
      delta
      htmlq
      graphviz
      shellcheck
      gron
      rlwrap
      dogdns
      git
      rtx
      tree
      broot
      # nix-du
      yq
      gh
      dive
      lazygit
      lazydocker
      rustup
      nushell
      glab
      zoxide
      hyperfine
      tmux
      ripgrep
      unzip
      fd
      htop
      jq
      xh
      watch
      xsv
      pv
      bat
      tokei
      soupault
      bottom
      wget
      certbot
      # for python
      packwiz # for meloncraft-modpack
      uv
      nix-output-monitor
    ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  # nix.package = pkgs.nixUnstable;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.allowed-users = [ "root" "natsume" ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    fish
    fishPlugins.pure
    veilid
    sqlite sqlite-interactive
  ];

  fileSystems."/mnt/reddit" = {
      device = "192.168.1.194:/volume1/project-reddit-data";
      fsType = "nfs";
      options = [ "nfsvers=4.1" "noatime" "x-systemd.automount" "noauto" "x-systemd.idle-timeout=60" "x-systemd.device-timeout=5s" "x-systemd.mount-timeout=5s"];
  };

  fileSystems."/mnt/stories" = {
      device = "192.168.1.194:/volume1/project-story-archive";
      fsType = "nfs";
      options = [ "nfsvers=4.1" "noatime" "x-systemd.automount" "noauto" "x-systemd.idle-timeout=60" "x-systemd.device-timeout=5s" "x-systemd.mount-timeout=5s"];
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.fish.enable = true;
  programs.mosh.enable = true;

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

  networking.firewall.allowedTCPPorts = [ 22 80 443 ];

  # power management for lower idle power draw
  powerManagement.powertop.enable = true;

  # cockpit for remote management
  services.cockpit = {
    enable = true;
    openFirewall = true;
    port = 9090;
  };

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

  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/etc/nixos/";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?

}
