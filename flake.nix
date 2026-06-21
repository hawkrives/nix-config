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

    blueprint = {
      url = "github:numtide/blueprint";
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

    ragenix = {
      url = "github:yaxitech/ragenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vpn-confinement = {
      # NOTE: this flake declares no inputs of its own, so no `inputs.nixpkgs.follows`.
      url = "github:Maroka-chan/VPN-Confinement";
    };

    # if we ever get an M-series server:
    # nixos-apple-silicon.url = "github:nix-community/nixos-apple-silicon";
  };

  # Load the blueprint
  outputs = inputs: {
    inherit
      (inputs.blueprint {
        inherit inputs;
        nixpkgs.config = {
          allowUnfree = true;
          allowInsecurePredicate = pkg: (builtins.parseDrvName pkg.name).name == "broadcom-sta";
        };
        nixpkgs.overlays = [
          (final: prev: {
            inherit (prev.lixPackageSets.latest)
              nixpkgs-review
              nix-direnv
              nix-eval-jobs
              nix-fast-build
              colmena
              ;

          })
        ];
      })
      checks
      devShells
      formatter
      lib
      templates
      darwinConfigurations
      nixosConfigurations
      # legacyPackages.<system>.homeConfigurations.<user>@<host> holds the
      # standalone Home Manager configs Blueprint builds from hosts/*/users/*.nix.
      # This is what `nh home switch` / `home-manager switch` auto-detect, so it
      # must be re-exported for `.#<user>@<host>` to resolve.
      legacyPackages
      modules
      homeModules
      darwinModules
      nixosModules
      packages
      ;

    customOutputs = { };
  };
}
