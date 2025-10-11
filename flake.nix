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

    serena.url = "github:oraios/serena";
    serena.inputs.nixpkgs.follows = "nixpkgs";

    # experimental; for managing the synology
    system-manager.url = "github:numtide/system-manager";
    system-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  # Load the blueprint
  outputs = inputs:
    inputs.blueprint {
      inherit inputs;
      nixpkgs.config.allowUnfree = true;
    };
}
