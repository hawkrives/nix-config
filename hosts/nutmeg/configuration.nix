{
  inputs,
  hostName,
  ...
}: {
  imports = [
    inputs.self.nixosModules.host-shared
    inputs.self.nixosModules.veilid-shared
    inputs.self.nixosModules.host-server

    ./adguard.nix
    ./home-assistant.nix
    ./plex.nix
    ./tailscale.nix

    # experimental
    ./freeradius.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # Define your hostname. Defaults to the folder this file is in.
  networking.hostName = hostName;

  # on nixos this either isNormalUser or isSystemUser is required to create the user.
  # TODO: understand this
  users.users.natsume = {
    isNormalUser = true;
    description = "Natsume";
    extraGroups = ["wheel"];
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # TODO: do we need this? what should it be?
  programs.nh.flake = "/home/natsume/nix-config#nutmeg";

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

  boot.initrd.availableKernelModules = [
    "ahci"
    "ehci_pci"
    "firewire_ohci"
    "sd_mod"
    "sdhci_pci"
    "uas"
    "usbhid"
    "xhci_pci"
  ];
  boot.initrd.kernelModules = [];
  boot.kernelModules = [
    "kvm-intel"
    "wl"
  ];

  # TODO: fix
  # boot.extraModulePackages = [config.boot.kernelPackages.broadcom_sta];

  # reduce IO cache, this should reduce latency when 2 processes try to read a lot from the disk
  # from <https://github.com/tchfoo/raspi-dotfiles/blob/8fd846f740385c92aa5f849944a2cd1a02d7d841/modules/system.nix>
  boot.kernel.sysctl = {
    "vm.dirty_background_ratio" = 10;
    "vm.dirty_ratio" = 40;
    "vm.vfs_cache_pressure" = 10;
  };

  # the bluetooth driver is insecure... but I want bluetooth readings from the house,
  # so we have to continue running it.
  nixpkgs.config.permittedInsecurePackages = [
    "broadcom-sta-6.30.223.271-57-6.12.41"
    "broadcom-sta-6.30.223.271-57-6.12.42"
    # TODO: can we just do this?
    # config.boot.kernelPackages.broadcom_sta
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/a049e035-2542-472e-ad90-4e0353d26185";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/67E3-17ED";
    fsType = "vfat";
  };

  swapDevices = [];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = true;

  hardware.cpu.intel.updateMicrocode = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
