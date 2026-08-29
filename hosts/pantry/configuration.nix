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
    flake.nixosModules.notify-failure
    flake.nixosModules.host-watch
    ./disk.nix
    ./networking.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = hostName;
  networking.useNetworkd = true;

  # Opt out of host-shared's 4g eval heap: this box has 3.9GB of RAM total, so
  # reserving that much would leave the collector no headroom to fall back on.
  # It's a build target anyway -- builders don't evaluate, so it gains nothing.
  environment.variables.GC_INITIAL_HEAP_SIZE = null;

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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILFhbHFf1LJ/NseB3yDEAKNu3CGNDs+ot8qdQA5LI4rU hawken.rives@Techcyte-DGQJV434PF"
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

  # ── Watch nutmeg from outside nutmeg ──────────────────────────────────
  #
  # Everything that monitors this fleet — the Beszel hub, Uptime Kuma, the
  # heartbeat receiver — runs ON nutmeg, so none of it can report nutmeg being
  # down. That is not hypothetical: nutmeg has silently hard-stopped three times
  # (hosts/nutmeg/crash-diagnostics.nix), once staying dead for 3.5 hours before
  # anyone walked over and pressed the power button.
  #
  # pantry is the natural place for the outside view: it is idle, it is not the
  # thing being watched, and it already reaches nutmeg over the tailnet. It does
  # NOT cover losing power to the whole house — both boxes are on the same feed,
  # and that needs an off-site check instead.
  age.secrets.telegram-notify.file = ../../secrets/telegram-notify.age;
  services.notifyFailure = {
    enable = true;
    tokenFile = config.age.secrets.telegram-notify.path;
  };

  services.hostWatch = {
    enable = true;
    targets.nutmeg = {
      # The tailnet IP, not nutmeg.local: mDNS resolution failing would make
      # this alert about the wrong thing, and nutmeg runs --accept-dns=false so
      # MagicDNS names do not resolve consistently across this fleet anyway.
      host = "100.70.139.99";
      port = 22; # sshd is socket-activated but the socket is up whenever the host is
      # 5 attempts × 60s = 5 minutes of silence before alerting. Long enough to
      # sit through a reboot or an `nh os switch` on nutmeg without paging.
      attempts = 5;
      gapSeconds = 60;
      onCalendar = "*:0/5";
    };
  };

  system.stateVersion = "26.11";
}
