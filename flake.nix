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
      # This is only ever used for its `age.*` module. We used to take that
      # module from the ragenix flake, but ragenix does not define one — its
      # flake does `inherit (agenix) nixosModules darwinModules
      # homeManagerModules`, passing agenix's through verbatim (both `default`s
      # are the same ./modules/age.nix). Going to the source drops ragenix,
      # crane and rust-overlay from the input graph, and with them the
      # rust-overlay `follows` workaround that lived here: ragenix pinned
      # rust-overlay to Oct 2025, which broke eval against current nixpkgs
      # (stdenv.isLinux/.isDarwin removal), so we had been tracking a fresh
      # rust-overlay ourselves purely to feed ragenix.
      #
      # The `ragenix` *binary* now comes from nixpkgs — see
      # modules/nixos/host-shared.nix.
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      # agenix's own darwin/home-manager test inputs; nothing here consumes
      # them, and letting them pull their own nixpkgs would undo the point.
      inputs.darwin.follows = "nix-darwin";
      inputs.home-manager.follows = "home-manager";
      inputs.systems.follows = "systems";
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
