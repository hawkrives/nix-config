{ ... }:
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
    # Hold network-online.target until this link can reach the LAN over IPv4.
    # The link meets the default state, "degraded", the moment it gains an
    # IPv6 link-local address — seconds before the DHCPv4 lease arrives. That
    # releases _netdev units early, and the NFS mounts they pull in fail with
    # "Network is unreachable", because the NAS answers at an IPv4 address
    # (see modules/nixos/synology-mounts.nix). tailscale0 is unmanaged, so
    # wait-online watches this link alone.
    linkConfig = {
      RequiredForOnline = "routable";
      RequiredFamilyForOnline = "ipv4";
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
  # This is an Apple EFI System Partition of only 197M, and a distinct
  # kernel+initrd pair costs ~58M, so three of them fill it. Without a cap the
  # ESP runs out and activation fails with ENOSPC. The installer
  # garbage-collects before it writes, so this is a hard bound rather than a
  # hope. Independent of nh clean, which prunes the profile, not the ESP.
  boot.loader.systemd-boot.configurationLimit = 3;
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
  ];

  # NOTE: the Broadcom STA driver (`wl` + broadcom_sta) used to live here, for
  # this Mac mini's BCM4331 wifi card. It was dropped: nutmeg has never used
  # wifi (it's on enp1s0f0, and wlp2s0 carried literally zero packets), while
  # the driver is unmaintained, out-of-tree, taints the kernel, and disables
  # kernel security mitigations where it runs ("Unpatched return thunk in use"
  # on every boot). It's also a known lockup source on these Broadcom Macs,
  # which matters given nutmeg's history of silent hard stops — see
  # ./crash-diagnostics.nix. If wifi is ever actually needed here, restore
  # broadcom_sta *and* the broadcom-sta allowInsecurePredicate in flake.nix.
  #
  # This does NOT affect bluetooth: hci0 is a separate USB device driven by
  # btusb + btbcm firmware, not by wl.

  # [firmware]
  # Load-bearing for bluetooth: this is what supplies the btbcm firmware that
  # hci0 needs (matter/home-assistant depend on it).
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # [bluetooth power management]
  # host-server.nix enables `powerManagement.powertop.enable`, and
  # `powertop --auto-tune` sets `power/control = auto` on every USB device —
  # including this Mac mini's BCM20702B0 bluetooth controller (05ac:828a at
  # USB 2-1.8.1.3). That controller does not survive a runtime suspend/resume
  # cycle: it comes back wedged, `hciconfig` still reports UP RUNNING, and every
  # HCI command then fails with -110 ("command 0x200c tx timeout"). BLE stops
  # dead. It wedged this way on 2026-08-05 after ~9 days uptime, having spent
  # more time suspended (9.6 days) than active (7.8 days), and took the Aranet
  # sensors offline for nine days.
  #
  # Recovering it needs a USB-level rebind — HA's own `bluetooth_auto_recovery`
  # cannot, because HCI resets time out against a dead controller and the
  # container deliberately has no NET_ADMIN (see ./home-assistant.nix):
  #   echo 2-1.8.1.3 | sudo tee /sys/bus/usb/drivers/usb/unbind
  #   sleep 3
  #   echo 2-1.8.1.3 | sudo tee /sys/bus/usb/drivers/usb/bind
  # then restart home-assistant, which otherwise clings to the stale socket.
  #
  # This is the module-level fix rather than a udev rule setting
  # `power/control = on`, deliberately: powertop runs as a boot service *after*
  # udev, so it would override such a rule and the trap would silently re-arm.
  # With autosuspend disabled in btusb itself, the kernel refuses to suspend the
  # device no matter what powertop writes. Scoped to btusb, so powertop's tuning
  # everywhere else is untouched.
  boot.extraModprobeConfig = ''
    options btusb enable_autosuspend=0
  '';

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
