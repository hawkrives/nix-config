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
      nixpkgsConfigValues = {
        allowUnfree = true;
        allowInsecurePredicate =
          pkg: (builtins.parseDrvName pkg.name).name == "broadcom-sta";
      };

      nixpkgsConfig =
        { ... }:
        {
          nixpkgs.config = nixpkgsConfigValues;
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

      # Build a standalone home-manager configuration (usable via
      # `home-manager switch --flake .#<name>`, or buildable directly with
      # `nix build .#homeConfigurations.<name>.activationPackage`). Unlike the
      # module wiring above, this does not depend on a surrounding NixOS/Darwin
      # system, so `osConfig` is absent for these.
      mkHome =
        {
          system,
          username,
          homeDirectory,
          modules,
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config = nixpkgsConfigValues;
          };
          extraSpecialArgs = { inherit inputs; };
          modules = modules ++ [
            {
              home.username = username;
              home.homeDirectory = homeDirectory;
            }
          ];
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

      # Standalone home-manager configurations. The names match the order
      # `home-manager switch` resolves them in: `<user>@<hostname>` first, then
      # bare `<user>`. The darwin entry mirrors the work Mac; the bare entry
      # targets Linux so it can be built/managed in cloud or CI sessions.
      homeConfigurations = {
        "hawken.rives@Techcyte-DGQJV434PF" = mkHome {
          system = "aarch64-darwin";
          username = "hawken.rives";
          homeDirectory = "/Users/hawken.rives";
          modules = [ ./hosts/Techcyte-DGQJV434PF/users/hawken.rives.nix ];
        };

        "hawken.rives" = mkHome {
          system = "x86_64-linux";
          username = "hawken.rives";
          homeDirectory = "/home/hawken.rives";
          modules = [ ./hosts/Techcyte-DGQJV434PF/users/hawken.rives.nix ];
        };
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
    };
}
