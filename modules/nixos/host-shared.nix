{
  pkgs,
  inputs,
  perSystem,
  ...
}: {
  # config settings for both NixOS- and Darwin-based systems

  imports = [inputs.lix-module.nixosModules.default];

  # "to enable vendor fish completions provided by Nixpkgs," says the nix wiki,
  # you need both this and the home-manager equivalent.
  # plus, I suppose it's nice to be able to drop into fish as root or w/e.
  programs.fish.enable = true;

  # Accept agreements for unfree software
  nixpkgs.config.allowUnfree = true;

  # you can check if host is darwin by using pkgs.stdenv.isDarwin
  environment.systemPackages =
    [
      pkgs.btop
      perSystem.nixpkgs-unstable.bottom
    ]
    ++ (pkgs.lib.optionals pkgs.stdenv.isLinux [
      # TODO: only install this on the NAS
      perSystem.nixpkgs-unstable.ghostty.terminfo
    ])
    ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [
      pkgs.xbar
      # install here because we use programs.nh.enable on linux
      perSystem.nixpkgs-unstable.nh
    ]);

  # some basic nix settings
  nix.settings = {
    # symlink identical paths in the store in the background
    # TODO: does lix support?
    auto-optimise-store = true;
    # enable flakes and the nice cli
    experimental-features = ["nix-command" "flakes"];
    # todo put the issue link here
    secret-key-files = "/etc/nix/private-key";
    # TODO I used to have this - needed?
    # allowed-users = ["root" "natsume"];

    # support pulling things from lix and flakehub
    extra-substituters = [
      "https://cache.lix.systems"
      "https://cache.flakehub.com"
    ];
    extra-trusted-public-keys =
      [
        "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
        # TODO: am I missing a key for flakehub?
      ]
      # plus my hosts
      ++ [
        "nutmeg:6F0E+NkIvpTI0d4QSvrDb3+LYhrQwXkYjqgI9etpuEw="
        "potato-bunny:i8Ab1IPNDKp9EWfmFDZIvMm70c+D435UlIsVFhJO3ts="
      ];
  };
}
