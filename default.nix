# Non-flake entry point, replacing Blueprint for nutmeg.
#
#   nix-build default.nix -A nixosConfigurations.nutmeg.config.system.build.toplevel
#   nh os switch --file . nixosConfigurations.nutmeg
#
# flake.nix is still here and still builds tuckles, pantry and Techcyte. This
# file is a second, parallel way to build *only* nutmeg, so the two can be
# diffed against each other before anything is committed to.
#
# Blueprint gave every host module four arguments — `inputs`, `flake`,
# `perSystem` and `hostName` — and derived the module list from the directory
# layout. Reproducing those four exactly is what lets this conversion touch
# zero files under hosts/ or modules/.
{
  system ? builtins.currentSystem,
  tamal ? import ./nix/tamal { inherit system; },
}:
let
  # Applied to every host, matching what flake.nix passes to Blueprint.
  nixpkgsConfig = {
    allowUnfree = true;
  };

  nixpkgsOverlays = [
    (_final: prev: {
      inherit (prev.lixPackageSets.latest)
        nixpkgs-review
        nix-direnv
        nix-eval-jobs
        nix-fast-build
        colmena
        ;
    })
  ];

  compat = import ./nix/compat.nix {
    inherit
      tamal
      system
      nixpkgsConfig
      nixpkgsOverlays
      ;
  };

  inherit (compat) inputs perSystem;
  inherit (compat.pkgs) lib;

  # Blueprint's `modules/<class>/<name>.nix -> <class>Modules.<name>` mapping,
  # including the `<name>/default.nix` directory form. Deliberately not
  # recursive: Blueprint isn't either, and service-channel-archive/ relies on
  # that (it holds Python helpers next to its default.nix).
  rake =
    dir:
    lib.pipe (builtins.readDir dir) [
      (lib.filterAttrs (
        name: type:
        (type == "regular" && lib.hasSuffix ".nix" name)
        || (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"))
      ))
      (lib.mapAttrs' (
        name: type:
        lib.nameValuePair (lib.removeSuffix ".nix" name) (
          import (dir + "/${name}" + lib.optionalString (type == "directory") "/default.nix")
        )
      ))
    ];

  # What Blueprint handed modules as `flake`: this repo's own outputs. Only the
  # module sets are ever read from it (`flake.nixosModules.*`,
  # `flake.homeModules.*`), so those are all it needs to carry.
  flake = {
    nixosModules = rake ./modules/nixos;
    homeModules = rake ./modules/home;
    darwinModules = rake ./modules/darwin;
  };

  specialArgs = {
    inherit inputs flake perSystem;
  };

  mkNixos =
    hostName:
    import "${tamal.nixpkgs}/nixos/lib/eval-config.nix" {
      # Left null on purpose: hosts set `nixpkgs.hostPlatform` themselves
      # (hosts/nutmeg/configuration.nix), and passing `system` here as well
      # makes eval-config throw about the two conflicting.
      system = null;
      specialArgs = specialArgs // { inherit hostName; };
      modules = [
        {
          nixpkgs.config = nixpkgsConfig;
          nixpkgs.overlays = nixpkgsOverlays;
        }
        (homeUsersModule hostName)
        ./hosts/${hostName}/configuration.nix
      ];
    };

  # Blueprint quietly enables Home Manager's NixOS module for any host with a
  # users/ directory, which is where the `home-manager-<user>.service` units
  # come from. Leaving this out was silently under-building nutmeg: the configs
  # evaluated standalone, but a `switch` would never have activated them.
  # `useGlobalPkgs`/`useUserPackages` and the mkDefault are Blueprint's too.
  # Guarded the way Blueprint guards it (`lib.optional (hasAttr hostname
  # homesNested)`), so a host with no users/ directory — pantry, today — stays
  # free of the Home Manager module rather than failing to read the directory.
  homeUsersModule =
    hostName:
    lib.optionalAttrs (builtins.pathExists ./hosts/${hostName}/users) {
      imports = [ (import "${tamal.home-manager}/nixos") ];
      home-manager.extraSpecialArgs = specialArgs // { inherit hostName; };
      home-manager.useGlobalPkgs = lib.mkDefault true;
      home-manager.useUserPackages = lib.mkDefault true;
      home-manager.users = lib.listToAttrs (
        map (user: lib.nameValuePair user ./hosts/${hostName}/users/${user}.nix) (homeUsers hostName)
      );
    };

  # Blueprint discovered hosts/<host>/users/<user>.nix as standalone Home
  # Manager configs and exposed them as `<user>@<host>`, which is the name
  # `nh home switch` and `home-manager switch` look for.
  mkHome =
    hostName: user:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = compat.pkgs;
      extraSpecialArgs = specialArgs // { inherit hostName; };
      modules = [
        {
          home.username = user;
          home.homeDirectory = "/home/${user}";
        }
        ./hosts/${hostName}/users/${user}.nix
      ];
    };

  homeUsers =
    hostName:
    lib.pipe (builtins.readDir ./hosts/${hostName}/users) [
      (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name))
      builtins.attrNames
      (map (lib.removeSuffix ".nix"))
    ];
in
rec {
  inherit
    tamal
    inputs
    flake
    perSystem
    ;

  nixosConfigurations.nutmeg = mkNixos "nutmeg";

  # Blueprint published these under legacyPackages.<system>.homeConfigurations,
  # which is where `nh home switch` and `home-manager switch` look. Reached here
  # as `-A homeConfigurations."natsume@nutmeg"`; neither CLI auto-detects a
  # non-flake path, so a standalone home switch needs the attribute spelled out.
  homeConfigurations = lib.listToAttrs (
    map (user: lib.nameValuePair "${user}@nutmeg" (mkHome "nutmeg" user)) (homeUsers "nutmeg")
  );

  # Convenience: what `nh os switch` ultimately builds.
  toplevel = nixosConfigurations.nutmeg.config.system.build.toplevel;

  # The pin manager itself, pinned by the thing it manages. Without this
  # `nixtamal refresh` needs an ambient nixtamal, which reintroduces exactly the
  # "which version of the tool locked this?" problem the lockfile exists to
  # avoid. Used by `mise run tamal:refresh`.
  packages.nixtamal = compat.pkgs.nixtamal;
}
