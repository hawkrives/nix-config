{
  inputs,
  lib,
  ...
}:
{
  imports = [
    # T2 kernel patches + apple-bce (keyboard/trackpad/audio bridge), Touch Bar,
    # APFS. Load-bearing for T2 support; no custom kernel flake needed.
    inputs.hardware.nixosModules.apple-t2
    # Fan-control daemon for T2 Macs. NOTE: nixosModules is plural (verified via
    # `nix flake show github:GnomedDev/T2FanRD`).
    inputs.t2fanrd.nixosModules.t2fanrd
  ];

  # The apple-t2 module compiles a patched kernel (and audio-patched
  # pipewire/pulseaudio) FROM SOURCE — a multi-hour build. Pull them from the
  # t2linux project's binary cache so bigpond downloads the kernel instead of
  # compiling it. mkAfter so this appends to host-shared's substituter list rather
  # than conflicting. (Third-party cache — the official t2linux one.)
  nix.settings.extra-substituters = lib.mkAfter [ "https://cache.soopy.moe" ];
  nix.settings.extra-trusted-public-keys = lib.mkAfter [
    "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo="
  ];

  # Active fan control under sustained build load. Default auto-config; tune the
  # curve later in /etc/t2fand.conf if needed.
  services.t2fanrd.enable = true;

  # Intel thermal daemon — avoid throttling/overheating during long builds.
  services.thermald.enable = true;

  # Headless laptop: never suspend, and ignore the (closed) lid.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  # host-server.nix enables `powerManagement.powertop.enable` (runs
  # `powertop --auto-tune`), which can autosuspend the USB-C ethernet adapter and
  # drop the network on this headless box. Force it off; thermald + t2fanrd handle
  # thermals.
  powerManagement.powertop.enable = lib.mkForce false;
}
