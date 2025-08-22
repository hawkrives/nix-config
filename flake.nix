{
  description = "NixOS (and nix-darwin) configuration for Hawken";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=release-25.05";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs?ref=nixpkgs-25.05-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs?ref=nixpkgs-unstable";

    systems.url = "github:nix-systems/default";
    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";
    blueprint.inputs.systems.follows = "systems";

    nix-darwin.url = "github:nix-darwin/nix-darwin?ref=nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    tsnsrv.url = "github:boinkor-net/tsnsrv";
    tsnsrv.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    home-manager.url = "github:nix-community/home-manager?ref=release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    lix-module.url = "https://git.lix.systems/lix-project/nixos-module/archive/2.93.3-1.tar.gz";
    lix-module.inputs.nixpkgs.follows = "nixpkgs";

    nil.url = "github:oxalica/nil?ref=2025-06-13";
    nil.inputs.nixpkgs.follows = "nixpkgs";

    alejandra.url = "github:kamadorueda/alejandra?ref=4.0.0";
    alejandra.inputs.nixpkgs.follows = "nixpkgs";
  };

  # Load the blueprint
  outputs = inputs:
    inputs.blueprint {
      inherit inputs;
      nixpkgs.config.allowUnfree = true;
    };

  # outputs = inputs @ {
  #   darwin,
  #   home-manager,
  #   lix-module,
  #   nixos-hardware,
  #   nixpkgs,
  #   nixpkgs-unstable,
  #   tsnsrv,
  #   nil,
  #   alejandra,
  #   ...
  # }: {
  #   # Build darwin flake using:
  #   # $ darwin-rebuild build --flake .#techcyted
  #   darwinConfigurations."Techcyte-XMG7K2VM6F" = let
  #     username = "hawken";
  #     system = "aarch64-darwin";
  #   in
  #     darwin.lib.darwinSystem {
  #       modules = [
  #         lix-module.nixosModules.default
  #         (import ./hosts/Techcyte-XMG7K2VM6F/configuration.nix {
  #           inherit username;
  #           hostname = "Techcyte-XMG7K2VM6F";
  #         })
  #         home-manager.darwinModules.home-manager
  #         {
  #           home-manager.useGlobalPkgs = true;
  #           home-manager.useUserPackages = true;
  #           home-manager.users.${username} = import ./users/${username}/home.nix {
  #             unstable-pkgs = import inputs.nixpkgs-unstable {inherit system;};
  #           };
  #         }
  #       ];
  #     };

  #   darwinConfigurations."Techcyte-DGQJV434PF" = let
  #     username = "hawken.rives";
  #     system = "aarch64-darwin";
  #     # pkgs = import nixpkgs { inherit system; };
  #   in
  #     darwin.lib.darwinSystem {
  #       modules = [
  #         lix-module.nixosModules.default
  #         (import ./hosts/Techcyte-DGQJV434PF/configuration.nix {
  #           inherit username;
  #           hostname = "Techcyte-DGQJV434PF";
  #           unstable-pkgs = import inputs.nixpkgs-unstable {inherit system;};
  #         })
  #         home-manager.darwinModules.home-manager
  #         {
  #           home-manager.useGlobalPkgs = true;
  #           home-manager.useUserPackages = true;
  #           home-manager.users.${username} = import ./users/hawken/home.nix {
  #             unstable-pkgs = import inputs.nixpkgs-unstable {inherit system;};
  #             nil = nil.packages.${system};
  #             alejandra = alejandra.packages.${system};
  #           };
  #         }
  #       ];
  #     };

  #   # Build linux flake using:
  #   # $ nixos-rebuild build --flake .#nutmeg
  #   nixosConfigurations.nutmeg = let
  #     system = "x86_64-linux";
  #   in
  #     nixpkgs.lib.nixosSystem {
  #       inherit system;
  #       modules = [
  #         ./common/hosts/linux.nix
  #         ./hosts/nutmeg/configuration.nix
  #         lix-module.nixosModules.default
  #       ];
  #       specialArgs = {
  #         pkgs-unstable = import nixpkgs-unstable {
  #           config.allowUnfree = true;
  #           inherit system;
  #         };
  #       };
  #     };

  #   # Build linux flake using:
  #   # $ nixos-rebuild build --flake .#pmx
  #   # nixosConfigurations.pmx-sonarr = let
  #   # in nixpkgs.lib.nixosSystem {
  #   #   system = "x86_64-linux";
  #   #   modules = [
  #   #     ./hosts/pmx-sonarr/configuration.nix
  #   #     lix-module.nixosModules.default
  #   #   ];
  #   # };
  # };
}
