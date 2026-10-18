{
  config,
  flake,
  hostName,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    flake.nixosModules.host-shared
    flake.nixosModules.host-server
    flake.nixosModules.host-nixos
    inputs.disko.nixosModules.default
    inputs.vpn-confinement.nixosModules.default
    flake.nixosModules.synology-mounts
    flake.nixosModules.service-backup
    flake.nixosModules.cache-push
    flake.nixosModules.notify-failure
    ./disk.nix
    ./networking.nix
    ./storage.nix
    ./sabnzbd.nix
    ./qbittorrent.nix
    ./slskd.nix
    ./bitmagnet.nix
    ./bitmagnet-watch.nix
    ./qui.nix
    ./tsnsrv.nix
    ./backups.nix

    inputs.tsnsrv.nixosModules.default
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = hostName;
  networking.useNetworkd = true;

  # disko sets boot.loader.grub.devices from disk.nix's `device`; setting it
  # here too would duplicate /dev/vda in mirroredBoots and fail an assertion.
  boot.loader.grub.enable = true;
  # Extend the root partition to fill /dev/vda at boot (see disk.nix).
  boot.growPartition = true;
  boot.initrd.availableKernelModules = [
    "ahci"
    "sd_mod"
    "ata_piix"
    "virtio_pci"
    "virtio_blk" # the virtio disk (/dev/vda) block driver — without it the
    "virtio_scsi" # initrd can't see the disk and root mount times out
  ];
  # Synology VMM's virtual GPU stalls the kernel's KMS console mid-boot; disable
  # mode-setting so the (headless) console keeps working. Without this the
  # installed system hangs right after `reached target Timer Units`.
  boot.kernelParams = ["nomodeset"];

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # Disk swap backing zswap (compression + oomd live in host-shared).
  swapDevices = [
    {
      device = "/swapfile";
      size = 4 * 1024; # MiB
    }
  ];

  users.users.haru = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.fish;

    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7JcUKxjlOrnEmQb7MgUmEZnTh8HPUoy84n5tmK4Ivs4aSpP6Q6Yh7OUCYRWjLHNGzXtRKqEgalDd8406KHvqcbDMs9LrR6ld0IlwVJpyibgs/wpukBzXJZgTaj3xXKhzFLECbxLey0EbJ/GHOXdywHKy1QQNs97PdtzK0XQazakQktp++V6MgRcCrzbTPTZVLcySlolSNpNFR4kAUVYK2xXKM145k74vKAoijsfWLBbNSXnx2sNYjKhWc2kpgiIDoJru9viFOIZZX0IJc/o9DT5eR+KoCNHTu5ioZ1x+Y8xSoVTFr+hjuQjZ3NFXeQ9sn08SjZtTsBZpDkJhI17hIEfPJ1vf4QDhS8Bz4yiaqiPMQ8j5Fr7ewa2zmT6Ocfk0rbseHXxZy91grQvl1NsMLGmzcdRd168Zv8du0OTHa4qu7vCUoLdx8S+NPnO57+QNxQDB97WFTBRjWxtbPcAKwBHjo3/zhW8ekFhtKEzdKCTlKd5N5E2UuIVsFE2O2itE= hawken@potato-bunny"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5cvA90dd+syRxeLBrQEdwBGmM4kC4pZBcbnya1g5sw natsume@nutmeg"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILFhbHFf1LJ/NseB3yDEAKNu3CGNDs+ot8qdQA5LI4rU hawken.rives@Techcyte-DGQJV434PF"
    ];
  };

  # tuckles runs no containers.
  virtualisation.podman.enable = false;

  environment.systemPackages = with pkgs; [
    curl
    btop
  ];

  programs.nh = {
    # todo: flake = "path#${hostName}";
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep-since 4d --keep 3";
    };
  };

  services.openssh = {
    # require public key authentication for better security
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
  };

  security.sudo.wheelNeedsPassword = false;

  age.secrets.wg-airvpn-tuckles.file = ../../secrets/wg-airvpn-tuckles.age;
  age.secrets.tailscale-authkey-tuckles.file = ../../secrets/tailscale-authkey-tuckles.age;
  age.secrets.qui-session-secret.file = ../../secrets/qui-session-secret.age;
  age.secrets.tsnsrv-authkey-tuckles.file = ../../secrets/tsnsrv-authkey-tuckles.age;
  age.secrets.telegram-notify.file = ../../secrets/telegram-notify.age;

  # Telegram push for failures of the units listed in services.notifyFailure.units
  # (bitmagnet-watch.nix), and the bot bitmagnet-watch reports matches through.
  services.notifyFailure = {
    enable = true;
    tokenFile = config.age.secrets.telegram-notify.path;
  };

  system.stateVersion = "26.11";
}
