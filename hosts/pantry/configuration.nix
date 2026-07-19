{
  flake,
  hostName,
  pkgs,
  inputs,
  config,
  ...
}:
{
  imports = [
    flake.nixosModules.host-shared
    flake.nixosModules.host-server
    flake.nixosModules.host-nixos
    inputs.disko.nixosModules.default
    ./disk.nix
    ./networking.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = hostName;
  networking.useNetworkd = true;

  # UEFI boot via systemd-boot. If VMM doesn't persist EFI NVRAM boot entries
  # across reboots, set canTouchEfiVariables = false and re-run the install.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = [
    "ahci"
    "sd_mod"
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
  ];
  # Synology VMM's virtual GPU stalls the kernel's KMS console mid-boot; disable
  # mode-setting so the (headless) console keeps working.
  boot.kernelParams = [ "nomodeset" ];

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # Disk swap backing zswap (compression + oomd live in host-shared).
  swapDevices = [
    {
      device = "/swapfile";
      size = 4 * 1024; # MiB
    }
  ];

  # Remote push user. nix copy writes arbitrary store paths, so this user must be
  # a trusted nix user. authorizedKeys are the *host* keys of every pushing/pulling
  # host (filled in Task 6).
  users.users.nixremote = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINRtF1Gu1NN25zb3ZWL+D2XBn2i0FszefxLVMwhItgOb" # nutmeg
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKaiGtVceXg9xJh0+jIIhFKZtnlNdPaWCZqSp0KNsb6r" # tuckles
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZW19gGFVWa3uCxOv4CHItnUuucmNQiExpgMAqTUSNO" # techcyte (mac, push + pull)
    ];
  };
  nix.settings.trusted-users = [ "nixremote" ];

  # Admin login.
  users.users.nix = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5cvA90dd+syRxeLBrQEdwBGmM4kC4pZBcbnya1g5sw natsume@nutmeg"
    ];
  };

  environment.systemPackages = with pkgs; [
    curl
    btop
  ];

  # Age-based retention GC (same mechanism as tuckles).
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

  age.secrets.tailscale-authkey-pantry.file = ../../secrets/tailscale-authkey-pantry.age;

  system.stateVersion = "26.11";
}
