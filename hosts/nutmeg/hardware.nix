{config, ...}: let
  broadcomDriver = config.boot.kernelPackages.broadcom_sta;
in {
  # [networking]
  # experimental; use systemd-networkd to manage interfaces
  networking.useNetworkd = true;
  services.resolved.enable = false; # systemd-resolved listens on :53, conflicting with adguard-home

  # [booting]
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # [kernel modules]
  boot.initrd.availableKernelModules = ["ahci" "ehci_pci" "firewire_ohci" "sd_mod" "sdhci_pci" "uas" "usbhid" "xhci_pci"];
  boot.initrd.kernelModules = [];
  boot.kernelModules = ["kvm-intel" "wl"];
  boot.extraModulePackages = [broadcomDriver];

  # the bluetooth driver is insecure... but I want bluetooth readings from the
  # house, so we have to continue running it.
  nixpkgs.config.permittedInsecurePackages = [broadcomDriver.name];

  # [firmware]
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # [swap]
  # disable disk swap and enable `zramSwap` to use a compressed block device in RAM
  swapDevices = [];
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # [filesystems]
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/a049e035-2542-472e-ad90-4e0353d26185";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/67E3-17ED";
    fsType = "vfat";
  };
}
