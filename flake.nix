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

    alejandra.url = "github:kamadorueda/alejandra?ref=4.0.0";
    alejandra.inputs.nixpkgs.follows = "nixpkgs";

    systemd-lsp.url = "github:jfryy/systemd-lsp?ref=v2025.07.14";
    systemd-lsp.inputs.nixpkgs.follows = "nixpkgs";

    nix-rosetta-builder.url = "github:cpick/nix-rosetta-builder";
    nix-rosetta-builder.inputs.nixpkgs.follows = "nixpkgs";
  };

  # Load the blueprint
  outputs = inputs:
    inputs.blueprint {
      inherit inputs;
      nixpkgs.config.allowUnfree = true;
    };
}
