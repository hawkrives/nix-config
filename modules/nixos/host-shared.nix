{
  pkgs,
  inputs,
  perSystem,
  ...
}: {
  imports = [inputs.lix-module.nixosModules.default];

  programs.neovim = {
    enable = true;
    package = perSystem.nixpkgs-unstable.neovim-unwrapped;
    withRuby = false;
    withNodeJs = false;
    withPython3 = false;
    vimAlias = true;
    viAlias = true;
  };

  # Accept agreements for unfree software
  nixpkgs.config.allowUnfree = true;

  # you can check if host is darwin by using pkgs.stdenv.isDarwin
  environment.systemPackages =
    [
      pkgs.btop
      perSystem.nixpkgs-unstable.bottom
      # TODO: only install this on the NAS
      perSystem.nixpkgs-unstable.ghostty.terminfo
    ]
    ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [pkgs.xbar]);

  # enable the nice nh tool (reimplements darwin-rebuild, nixos-rebuild, etc)
  # <https://schmiggolas.dev/posts/2024/nh/>
  programs.nh = {
    enable = true;
    package = perSystem.nixpkgs-unstable.nh;
  };

  # "to enable vendor fish completions provided by Nixpkgs," says the nix wiki,
  # you need both this and the home-manager equivalent.
  # plus, I suppose it's nice to be able to drop into fish as root or w/e.
  programs.fish.enable = true;

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

  virtualisation.oci-containers.backend = "podman";
  virtualisation.podman.enable = true;
  # periodically prune Podman resources
  virtualisation.podman.autoPrune.enable = true;
  # Create a `docker` alias for podman, to use it as a drop-in replacement
  virtualisation.podman.dockerCompat = true;
  # Required for containers under podman-compose to be able to talk to each other.
  # virtualisation.podman.defaultNetwork.settings.dns_enabled = true;
}
