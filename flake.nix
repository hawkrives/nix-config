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

    agenix = {
      url = "github:ryantm/agenix";
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

    slime-chat = {
      url = "git+https://github.com/hawkrives/slime2-twitch-chat";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    t2fanrd = {
      # Fan-control daemon for T2 Macs (bigpond). Staged but NOT yet imported —
      # deferred until a nixpkgs update fixes its crates.io cargo-vendor fetch
      # without moving the kernel off the soopy cache (see hosts-disabled/bigpond/hardware.nix).
      url = "github:GnomedDev/T2FanRD";
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
          # (the broadcom-sta allowInsecurePredicate that used to live here went
          # away with nutmeg's `wl` driver — see hosts/nutmeg/hardware.nix)
        };
        nixpkgs.overlays = [
          (
            final: prev:
            let
              lix = prev.lixPackageSets.latest;
            in
            {
              # nix-eval-jobs is built from source inside the Lix package set, so
              # naming it here is safe. Lix's own overlay takes this one attribute
              # from the set for the same reason.
              inherit (lix) nix-eval-jobs;

              # The rest are *arguments* to the Lix package set: it defines them as
              # `nix-direnv.override { nix = self.lix; }`, where `nix-direnv` comes
              # from the final package set. Inheriting them from the set would point
              # the set back at this overlay and recurse forever, so apply the same
              # overrides the set applies, reading the base package from prev.
              nix-direnv = prev.nix-direnv.override { nix = lix.lix; };
              nixpkgs-review = prev.nixpkgs-review.override { nix = lix.lix; };
              nix-fast-build = prev.nix-fast-build.override {
                inherit (lix) nix-eval-jobs;
              };
              colmena = prev.colmena.override {
                nix = lix.lix;
                inherit (lix) nix-eval-jobs;
              };
            }
          )
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
