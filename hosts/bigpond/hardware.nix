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
    # NOTE: t2fanrd (a TUNED fan curve) is DEFERRED. Its cargo-vendor build hits
    # crates.io's 403'd legacy `api/v1/.../download` endpoint on this nixpkgs pin,
    # and bumping nixpkgs to fix it moves the kernel off the soopy cache (forcing a
    # from-source compile). The apple-t2 kernel already includes applesmc T2 fan
    # support, so fans WORK; thermald handles thermals. Re-add
    # `inputs.t2fanrd.nixosModules.t2fanrd` + `services.t2fanrd.enable` in a
    # follow-up once a nixpkgs update brings BOTH a cached kernel and the
    # static.crates.io fetcher. (The `t2fanrd` flake input stays, primed for that.)
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

  # Intel thermal daemon — avoid throttling/overheating during long builds. Fans
  # themselves are driven by the kernel's applesmc T2 support; the tuned t2fanrd
  # curve is deferred (see imports note).
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
  # drop the network on this headless box. Force it off; thermald + the kernel's
  # applesmc fan support handle thermals.
  powerManagement.powertop.enable = lib.mkForce false;
}
