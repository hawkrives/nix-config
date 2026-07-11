{
  flake,
  hostName,
  pkgs,
  inputs,
  config,
  lib,
  ...
}:
{
  imports = [
    flake.nixosModules.host-shared
    flake.nixosModules.host-server
    flake.nixosModules.host-nixos
    flake.nixosModules.cache-push
    inputs.disko.nixosModules.default
    ./disk.nix
    ./networking.nix
    ./hardware.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = hostName;
  networking.useNetworkd = true;

  # UEFI boot via systemd-boot (t2linux-recommended).
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  swapDevices = [ ];
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # Builder parallelism cap: keep heavy parallel builds from starving future
  # co-located services on this 15 GiB box (see spec). Tune if builds feel slow.
  nix.settings.max-jobs = 4;
  nix.settings.cores = 4;

  # Tailscale auth key, decrypted at activation via this host's host key.
  age.secrets.tailscale-authkey-bigpond.file = ../../secrets/tailscale-authkey-bigpond.age;

  # Primary admin user.
  users.users.pinklady = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5cvA90dd+syRxeLBrQEdwBGmM4kC4pZBcbnya1g5sw" # natsume
    ];
  };

  # Trusted push/build user. authorizedKeys are the *host* keys of the hosts that
  # offload builds to bigpond (nutmeg + the Mac); nix copy / remote build run as
  # this trusted user.
  users.users.nixremote = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINRtF1Gu1NN25zb3ZWL+D2XBn2i0FszefxLVMwhItgOb" # nutmeg
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZW19gGFVWa3uCxOv4CHItnUuucmNQiExpgMAqTUSNO" # techcyte (mac)
    ];
  };
  nix.settings.trusted-users = [ "nixremote" ];

  # Age-based retention GC (same mechanism as pantry/tuckles).
  programs.nh.clean = {
    enable = true;
    dates = "weekly";
    extraArgs = "--keep-since 90d --keep 5";
  };

  services.openssh = {
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    curl
    btop
  ];

  system.stateVersion = "26.11";
}
