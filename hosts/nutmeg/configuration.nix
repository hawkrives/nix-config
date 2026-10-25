{
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
    flake.nixosModules.synology-mounts
    flake.nixosModules.service-backup
    flake.nixosModules.service-channel-archive
    flake.nixosModules.cache-push
    flake.nixosModules.notify-failure
    flake.nixosModules.unit-heartbeat
    flake.nixosModules.live-notify

    # configuration
    ./hardware.nix
    ./crash-diagnostics.nix
    ./ssd-writes.nix

    # modules
    ./adguard.nix
    ./aurral.nix
    ./home-assistant.nix
    ./home-assistant-matter.nix
    ./trawl.nix
    ./plex.nix
    ./servarr.nix
    ./service-hardening.nix
    ./beets.nix
    ./channel-archive.nix
    ./channel-archive-backlog.nix
    ./recyclarr.nix
    ./tailscale.nix
    ./peertube.nix
    ./micasa.nix
    ./minecraft.nix
    ./slime-chat.nix
    ./tsnsrv.nix
    ./backups.nix
    ./restic.nix
    ./uptime-kuma.nix
    ./live-notify.nix
    ./stream-watch.nix
    ./beszel.nix
    ./mbx.nix

    inputs.nix-minecraft.nixosModules.minecraft-servers
    inputs.tsnsrv.nixosModules.default
  ];

  nixpkgs.overlays = [inputs.nix-minecraft.overlay];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = hostName; # hostName is detected by Blueprint; defaults to the containing folder's name

  services.mbpfan.enable = true; # enable Mac fan control daemon

  # The quad-core i7 in this mini can't shed a sustained all-thread load: the
  # fan pins at max and the package throttles against its 105 °C TjMax. Cap
  # builds at ~4 busy threads (2 derivations x 2 cores). Cargo inside Nix
  # builds follows `cores` via NIX_BUILD_CORES; CARGO_BUILD_JOBS covers cargo
  # run outside the sandbox.
  nix.settings = {
    max-jobs = 2;
    cores = 2;
  };
  environment.variables.CARGO_BUILD_JOBS = "2";
  systemd.coredump.enable = false; # disable core dumps

  # ragenix example secret; decrypted to /run/agenix/example at activation via
  # this host's /etc/ssh/ssh_host_ed25519_key. Recipients live in secrets/secrets.nix.
  age.secrets.example.file = ../../secrets/example.age;

  users.users."natsume" = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.fish;
  };

  # Passwordless sudo on this box (nutmeg). Scoped here rather than in the shared
  # host-server module so it doesn't relax sudo on every server. natsume is the
  # only wheel member here, so this effectively grants it to natsume;
  # host-server keeps execWheelOnly on.
  security.sudo.wheelNeedsPassword = false;

  # for slime. TCP only — slime-chat is an HTTP server, so the UDP half of this
  # rule never matched anything.
  networking.firewall.allowedTCPPorts = [9100];

  programs.nh = {
    flake = "/home/natsume/nix-config#${hostName}";
    clean.enable = true;
    clean.dates = "weekly";
    clean.extraArgs = "--keep-since 4d --keep 3";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
