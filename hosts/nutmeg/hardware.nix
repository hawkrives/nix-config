{ config, ... }:
let
  broadcomDriver = config.boot.kernelPackages.broadcom_sta;
in
{
  # [networking]
  networking.useNetworkd = true;
  services.resolved.enable = true;

  # have nutmeg resolve through adguardhome, but keep a
  # fallback around in case adguard is down
  services.resolved.settings.Resolve.Domains = [ "~." ];
  services.resolved.settings.Resolve.FallbackDNS = [
    "1.1.1.1"
    "2606:4700:4700::1111"
  ];
  networking.nameservers = [ "192.168.1.228" ];

  systemd.network.networks."10-lan" = {
    matchConfig.Name = "enp1s0f0";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = true;
    };
    ipv6AcceptRAConfig.Token = "static:::228";
    # Pin the global ::228 statically so it survives gaps between the router's
    # RAs — the whole LAN is told to use this address for DNS (adguard), so it
    # must not lapse. The SLAAC token above still derives the same address from
    # the RA; this just guarantees it's always present.
    # NOTE: update this if the ISP-delegated prefix ever changes (currently
    # 2600:2b00:9b16:6d01::/64).
    address = [ "2600:2b00:9b16:6d01::228/64" ];
  };

  # [booting]
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # [kernel modules]
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
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [
    "kvm-intel"
    "wl"
  ];
  boot.extraModulePackages = [ broadcomDriver ];

  # [firmware]
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # [swap]
  # Disk swap backing zswap (compression + oomd configured in host-shared).
  swapDevices = [
    {
      device = "/swapfile";
      size = 8 * 1024; # MiB
    }
  ];

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
