{
  pkgs,
  inputs,
  perSystem,
  lib,
  config,
  ...
}: {
  # config settings for both NixOS- and Darwin-based systems
  imports = [];

  # "to enable vendor fish completions provided by Nixpkgs," says the nix wiki,
  # you need both this and the home-manager equivalent.
  # plus, I suppose it's nice to be able to drop into fish as root or w/e.
  programs.fish.enable = true;

  # Accept agreements for unfree software
  # nixpkgs.config.allowUnfree = true;

  # Install fonts
  fonts = {
    packages = [pkgs.nerd-fonts.blex-mono];
    # enableDefaultPackages = true;
  };

  # [memory management] zswap + systemd-oomd, applied to every Linux host.
  #
  # zswap is a compressed writeback cache that sits in FRONT of real disk swap:
  # hot anonymous pages are compressed in RAM, and cold ones are evicted down to
  # the swapfile (defined per-host, since each host picks its own size). This
  # replaces the old standalone zramSwap, which had no backing store — under
  # sustained memory pressure it could only OOM or hang for minutes rather than
  # tier cold pages to disk.
  # https://chrisdown.name/2026/03/24/zswap-vs-zram-when-to-use-what.html
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
    "zswap.max_pool_percent=20"
  ];

  # systemd-oomd is enabled by default in NixOS, but NixOS ships it with every
  # slice monitor OFF, so the daemon runs without ever acting. Turn on all three
  # so oomd kills the worst-offending cgroup under real memory/swap pressure,
  # before the kernel OOM killer (or a multi-minute brownout) would.
  systemd.oomd = {
    enableRootSlice = true;
    enableSystemSlice = true;
    enableUserSlices = true;
  };

  # you can check if host is darwin by using pkgs.stdenv.isDarwin
  environment.systemPackages =
    [
      pkgs.btop
      pkgs.rage
      perSystem.ragenix.default
    ]
    ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [
      # TODO: only install this on the NAS
      pkgs.ghostty.terminfo
    ])
    ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [
      # install here because we use programs.nh.enable on linux
      pkgs.nh
    ]);

  nix.package = pkgs.lixPackageSets.latest.lix;

  # TODO: document
  nix.optimise.automatic = true;

  # set the default system nixpkgs (used by `nix shell nixpkgs#cowsay`, etc.) to
  # the one specified in the flake inputs
  nix.registry.nixpkgs.flake = inputs.nixpkgs;

  # some basic nix settings
  nix.settings = {
    # enable flakes and the nice cli
    experimental-features = ["nix-command" "flakes"];
    # todo put the issue link here
    # nix key generate-secret --key-name (hostname) | sudo tee /etc/nix/private-key
    # cat /etc/nix/private-key | nix key convert-secret-to-public
    secret-key-files = "/etc/nix/private-key";
    # TODO I used to have this - needed?
    # allowed-users = ["root" "natsume"];

    # auto-GC mid-build when free space runs low, so a heavy build self-cleans
    # instead of filling the disk (esp. nutmeg's small SSD): 5 GiB low-water,
    # free up to 20 GiB.
    min-free = 5 * 1024 * 1024 * 1024;
    max-free = 20 * 1024 * 1024 * 1024;

    # support pulling things from lix and flakehub, plus the pantry cache (over
    # the tailnet; the host-key is pinned so no known_hosts is needed). pantry
    # doesn't substitute from itself. nutmeg runs --accept-dns=false so we use
    # pantry's stable tailnet IP rather than its MagicDNS name.
    extra-substituters =
      [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ]
      ++ lib.optionals (config.networking.hostName != "pantry") [
        "ssh-ng://nixremote@100.120.197.118?ssh-key=/etc/ssh/ssh_host_ed25519_key&base64-ssh-public-host-key=c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUJpVVEwUGxtMmNlb25WRVJBUDBtNU5vRUgzOUozakNzdXhRZ094VzFLNjc="
      ];
    extra-trusted-public-keys =
      [
        "cache:fWnI+McRUwqFqvEzDFkCOU256xHHztm+SR1l2UWGZzU="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ]
      # plus my hosts
      ++ [
        "nutmeg:6F0E+NkIvpTI0d4QSvrDb3+LYhrQwXkYjqgI9etpuEw="
        "potato-bunny:i8Ab1IPNDKp9EWfmFDZIvMm70c+D435UlIsVFhJO3ts="
        "Techcyte-DGQJV434PF:2Xo6QORWHHSNQHveplJ1Fq1Ji8GXwtm7FsD4l/tM/0I="
        "tuckles:QXDvYTGgHgAIo/EzWTn/UcTuKZEP1MqsQsX9/3apQsc="
      ];
  };
}
