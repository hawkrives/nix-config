{
  pkgs,
  perSystem,
  ...
}: let
  p = perSystem.nixpkgs-unstable;
in {
  # config settings for both NixOS- and Darwin-based systems

  imports = [];

  # "to enable vendor fish completions provided by Nixpkgs," says the nix wiki,
  # you need both this and the home-manager equivalent.
  # plus, I suppose it's nice to be able to drop into fish as root or w/e.
  programs.fish.enable = true;

  # Accept agreements for unfree software
  nixpkgs.config.allowUnfree = true;

  # Install fonts
  fonts = {
    packages = [p.nerd-fonts.blex-mono];
    # enableDefaultPackages = true;
  };

  # you can check if host is darwin by using pkgs.stdenv.isDarwin
  environment.systemPackages =
    [
      pkgs.btop
      p.bottom
    ]
    ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [
      # TODO: only install this on the NAS
      p.ghostty.terminfo
    ])
    ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [
      # install here because we use programs.nh.enable on linux
      p.nh
    ]);

  nixpkgs.overlays = [
    (final: prev: {
      inherit
        (final.lixPackageSets.stable)
        nixpkgs-review
        nix-direnv
        nix-eval-jobs
        nix-fast-build
        colmena
        ;
    })
  ];

  nix.package = pkgs.lixPackageSets.stable.lix;

  # TODO: document
  nix.optimise.automatic = true;

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

    # support pulling things from lix and flakehub
    extra-substituters = [
      "https://cache.nixos.org"
      "https://cache.lix.systems"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys =
      [
        "cache:fWnI+McRUwqFqvEzDFkCOU256xHHztm+SR1l2UWGZzU="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ]
      # plus my hosts
      ++ [
        "nutmeg:6F0E+NkIvpTI0d4QSvrDb3+LYhrQwXkYjqgI9etpuEw="
        "potato-bunny:i8Ab1IPNDKp9EWfmFDZIvMm70c+D435UlIsVFhJO3ts="
        "Techcyte-DGQJV434PF:2Xo6QORWHHSNQHveplJ1Fq1Ji8GXwtm7FsD4l/tM/0I="
      ];
  };
}
