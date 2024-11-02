{
  description = "NixOS (and nix-darwin) configuration";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-24.05-darwin";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    darwin.url = "github:LnL7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    tsnsrv.url = "github:boinkor-net/tsnsrv";
    tsnsrv.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    home-manager.url = "github:nix-community/home-manager/release-24.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    lix-module.url = "https://git.lix.systems/lix-project/nixos-module/archive/2.91.1.tar.gz";
    lix-module.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs = inputs@{
    darwin,
    home-manager,
    lix-module,
    nixos-hardware,
    nixpkgs,
    tsnsrv,
    ...
  }: {
    nixpkgs.config.allowUnfree = true;

    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#techcyted
    darwinConfigurations."Techcyte-XMG7K2VM6F" = let
      username = "hawken";
      system = "aarch64-darwin";
    in darwin.lib.darwinSystem {
      modules = [
        lix-module.nixosModules.default
        (import ./hosts/Techcyte-XMG7K2VM6F/configuration.nix {
          inherit username;
          hostname = "Techcyte-XMG7K2VM6F";
        })
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.${username} = import ./users/${username}/home.nix ({
            unstable-pkgs = (import inputs.nixpkgs-unstable { inherit system; });
          });
        }
      ];
    };

    # Build linux flake using:
    # $ nixos-rebuild build --flake .#nutmeg
    nixosConfigurations.nutmeg = let
    in nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/nutmeg/configuration.nix
        lix-module.nixosModules.default
      ];
    };

    # Build linux flake using:
    # $ nixos-rebuild build --flake .#pmx
    nixosConfigurations.pmx-sonarr = let
    in nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/pmx-sonarr/configuration.nix
        lix-module.nixosModules.default
      ];
    };

  };
}
