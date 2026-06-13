{
  description = "NixOS (and nix-darwin) configuration for Hawken";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

    hardware.url = "github:NixOS/nixos-hardware";
    systems.url = "github:nix-systems/default";

    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin?ref=master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tsnsrv = {
      url = "github:boinkor-net/tsnsrv";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager?ref=master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    micasa = {
      # home management database
      url = "github:cpcloud/micasa?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.inputs.systems.follows = "systems";
    };

    agenix = {
      url = "github:ryantm/agenix?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = "nix-darwin";
      inputs.home-manager.follows = "home-manager";
      inputs.systems.follows = "systems";
    };

    # if we ever get an M-series server:
    # nixos-apple-silicon.url = "github:nix-community/nixos-apple-silicon";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      systems,
      ...
    }:
    let
      lib = nixpkgs.lib;

      forAllSystems = lib.genAttrs (import systems);

      # nixpkgs settings that used to live in the blueprint call.
      nixpkgsConfig =
        { ... }:
        {
          nixpkgs.config = {
            allowUnfree = true;
            allowInsecurePredicate =
              pkg: (builtins.parseDrvName pkg.name).name == "broadcom-sta";
          };
        };

      # Wire a set of home-manager users ({ name = path; }) into a system
      # configuration. The home-manager NixOS/Darwin module provides `pkgs`,
      # `osConfig`, etc. to each user module automatically.
      homeUsers =
        users:
        { ... }:
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users = builtins.mapAttrs (_name: path: import path) users;
        };

      mkNixos =
        {
          modules,
          users ? { },
        }:
        lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            nixpkgsConfig
            home-manager.nixosModules.home-manager
            (homeUsers users)
          ] ++ modules;
        };

      mkDarwin =
        {
          modules,
          users ? { },
        }:
        nix-darwin.lib.darwinSystem {
          specialArgs = { inherit inputs; };
          modules = [
            nixpkgsConfig
            home-manager.darwinModules.home-manager
            (homeUsers users)
          ] ++ modules;
        };
    in
    {
      nixosConfigurations = {
        nutmeg = mkNixos {
          modules = [ ./hosts/nutmeg/configuration.nix ];
          users = {
            natsume = ./hosts/nutmeg/users/natsume.nix;
            techcyte = ./hosts/nutmeg/users/techcyte.nix;
          };
        };

        tuckles = mkNixos {
          modules = [ ./hosts/tuckles/configuration.nix ];
        };
      };

      darwinConfigurations = {
        "Techcyte-DGQJV434PF" = mkDarwin {
          modules = [ ./hosts/Techcyte-DGQJV434PF/darwin-configuration.nix ];
          users = {
            "hawken.rives" = ./hosts/Techcyte-DGQJV434PF/users/hawken.rives.nix;
          };
        };
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
    };
}
