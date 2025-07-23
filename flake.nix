{
  description = "NixOS (and nix-darwin) configuration for Hawken";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.05";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    tsnsrv.url = "github:boinkor-net/tsnsrv";
    tsnsrv.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    lix-module.url = "https://git.lix.systems/lix-project/nixos-module/archive/2.93.2-1.tar.gz";
    lix-module.inputs.nixpkgs.follows = "nixpkgs";

    unison-lang.url = "github:ceedubs/unison-nix";
    unison-lang.inputs.nixpkgs.follows = "nixpkgs";

    flox.url = "github:flox/flox/v1.5.0";
  };

  outputs = inputs@{
    darwin,
    home-manager,
    lix-module,
    nixos-hardware,
    nixpkgs,
    nixpkgs-unstable,
    tsnsrv,
    unison-lang,
    flox,
    ...
  }: {

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

    darwinConfigurations."Techcyte-DGQJV434PF" = let
      username = "hawken.rives";
      system = "aarch64-darwin";

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ unison-lang.overlay ];
      };
    in darwin.lib.darwinSystem {
      modules = [
        lix-module.nixosModules.default
        (import ./hosts/Techcyte-DGQJV434PF/configuration.nix {
          inherit username;
          hostname = "Techcyte-DGQJV434PF";
          flox = flox;
          unstable-pkgs = (import inputs.nixpkgs-unstable { inherit system; });
        })
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.${username} = import ./users/hawken/home.nix ({
            unstable-pkgs = (import inputs.nixpkgs-unstable { inherit system; });
          });
        }
      ];
    };

    # Build linux flake using:
    # $ nixos-rebuild build --flake .#nutmeg
    nixosConfigurations.nutmeg = let
      system = "x86_64-linux";
    in nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./hosts/nutmeg/configuration.nix
        lix-module.nixosModules.default
      ];
      specialArgs = {
        pkgs-unstable = import nixpkgs-unstable {
          config.allowUnfree = true;
          inherit system;
        };
      };
    };

    # Build linux flake using:
    # $ nixos-rebuild build --flake .#pmx
    # nixosConfigurations.pmx-sonarr = let
    # in nixpkgs.lib.nixosSystem {
    #   system = "x86_64-linux";
    #   modules = [
    #     ./hosts/pmx-sonarr/configuration.nix
    #     lix-module.nixosModules.default
    #   ];
    # };

  };
}
