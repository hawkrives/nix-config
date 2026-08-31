{
  pkgs,
  inputs,
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

  # you can check if host is darwin by using pkgs.stdenv.hostPlatform.isDarwin
  environment.systemPackages =
    [
      pkgs.btop
      pkgs.rage
      # The CLI, from nixpkgs rather than built from the ragenix flake through
      # crane + a pinned rust-overlay. See the agenix input in flake.nix for
      # why the flake went away.
      #
      # nixpkgs builds the 2025.03.09 tag where the flake built main. That
      # sounds like a downgrade and isn't: 2025.03.09 is the only tag ragenix
      # has ever cut, and the three commits between it and the rev we pinned
      # are a lazy_static -> std::LazyLock refactor and two flake.lock bumps.
      # No CLI, age-format or rules-schema changes.
      #
      # The last of those bumps was titled "fix build on newer nixpkgs" — which
      # is what we were tracking main for. It only touches ragenix's *own*
      # flake.lock, so it cannot matter here: nixpkgs never reads that flake,
      # it builds the source tarball with its own Rust toolchain. Which is also
      # why the rust-overlay workaround can't come back on this path.
      pkgs.ragenix
    ]
    ++ (pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      # TODO: only install this on the NAS
      pkgs.ghostty.terminfo
    ])
    ++ (pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      # install here because we use programs.nh.enable on linux
      pkgs.nh
    ]);

  # Nix's evaluator is single-threaded and, on a host config this size, spends a
  # good slice of its run collecting against a ~1.6GB working set. Handing Boehm
  # a big heap up front skips most of the early collections. Measured on nutmeg
  # over four paired full evals of its own toplevel: mean eval CPU 41.9s -> 36.2s
  # (-14%). 6g measured no better and 2g measured worse, so 4g is the knee. This
  # is address space, faulted in lazily, so small evals don't really pay 4GB.
  #
  # This is the biggest lever available in-config; the eval itself is ~95% of the
  # wall time of an `nh os switch` that has to re-evaluate at all. (It only has
  # to when something changed: Lix caches per flake source fingerprint, so an
  # unchanged tree short-circuits to ~2s, and any edit invalidates the lot.)
  #
  # mkDefault so memory-tight hosts can opt out -- see pantry.
  environment.variables.GC_INITIAL_HEAP_SIZE = lib.mkDefault "4g";

  nix.package = pkgs.lixPackageSets.latest.lix;

  # TODO: document
  nix.optimise.automatic = true;

  # set the default system nixpkgs (used by `nix shell nixpkgs#cowsay`, etc.) to
  # the one specified in the flake inputs
  nix.registry.nixpkgs.flake = inputs.nixpkgs;

  # this fleet is flake-only and root is subscribed to no channels, so the
  # default NIX_PATH entry for /nix/var/nix/profiles/per-user/root/channels
  # points at a directory that never gets created — every `nix` invocation then
  # warns about the dangling search path entry. Turning channels off drops that
  # entry (NIX_PATH becomes just "nixpkgs=flake:nixpkgs", pinned above by
  # nixpkgs.flake.setNixPath) at the cost of removing the `nix-channel` command,
  # which nothing here uses.
  nix.channel.enable = false;

  # This host's binary-cache signing key. It used to be hand-generated into
  # /etc/nix/private-key, which made it the one piece of fleet identity that
  # wasn't declarative — so when pantry was reinstalled the key vanished, and
  # since nix opens secret-key-files at the end of every build, *every* build on
  # pantry then died with "opening file '/etc/nix/private-key': No such file or
  # directory". Keeping it in ragenix means it survives a reinstall and the
  # public half stays stable, so extra-trusted-public-keys below stays correct.
  #
  # One file per host, named for networking.hostName; a host without one fails
  # at eval rather than at the end of its first build.
  age.secrets.nix-signing-key.file = ../../secrets/nix-signing-key-${config.networking.hostName}.age;

  # some basic nix settings
  nix.settings = {
    # enable flakes and the nice cli
    experimental-features = ["nix-command" "flakes"];
    # Regenerate with:
    #   nix key generate-secret --key-name (hostname) > key
    #   nix key convert-secret-to-public < key   # -> extra-trusted-public-keys
    # then re-encrypt it: see secrets/secrets.nix.
    secret-key-files = config.age.secrets.nix-signing-key.path;
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
    # Nix keeps these as a name -> key map, so a name appears at most once:
    # re-keying a host replaces trust for everything it signed before, it does
    # not add to it. (The old "cache:..." entry here was pantry's key from
    # before its reinstall; the private half is gone, so nothing could ever
    # produce a matching signature again. Dropped.)
    extra-trusted-public-keys =
      [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ]
      # plus my hosts. nutmeg and tuckles carry their original keys, adopted
      # into ragenix as-is so nothing they have already pushed goes stale.
      # pantry is new (it never had one). Techcyte's is a fresh key, replacing
      # 2Xo6QORWHHSNQHveplJ1Fq1Ji8GXwtm7FsD4l/tM/0I= — only ever used on
      # aarch64-darwin paths, which no other host here can consume anyway.
      ++ [
        "nutmeg:6F0E+NkIvpTI0d4QSvrDb3+LYhrQwXkYjqgI9etpuEw="
        "pantry:eH1y5GJInQcb8pW/gXQq5GiMiszHIjhqpeMgktIDOQA="
        "potato-bunny:i8Ab1IPNDKp9EWfmFDZIvMm70c+D435UlIsVFhJO3ts="
        "Techcyte-DGQJV434PF:FDqhahy007nFE2T8Cj5sBu7uacsP5N9V9dbuERDeeSc="
        "tuckles:QXDvYTGgHgAIo/EzWTn/UcTuKZEP1MqsQsX9/3apQsc="
      ];
  };
}
