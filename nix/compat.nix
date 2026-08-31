# De-flaking shims.
#
# Nixtamal pins *source trees*. It has no idea what a flake output is. But nine
# tenths of what this repo asked its inputs for was flake outputs —
# `inputs.tsnsrv.nixosModules.default`, `inputs.nix-minecraft.overlay`,
# `perSystem.ragenix.default`. So something has to turn a directory back into
# the attrset the existing modules expect.
#
# That something is this file. It reconstructs, by hand, the subset of each
# upstream flake's outputs that nutmeg actually consumes. Nothing under
# hosts/ or modules/ changes: they still receive `inputs`, `flake` and
# `perSystem` with the same shapes Blueprint gave them.
#
# The cost is visible right here — each entry below is a hand-maintained
# restatement of someone else's flake.nix, and it can drift when they refactor.
# Read this file as the honest price tag on the conversion.
{
  tamal,
  system,
  nixpkgsConfig,
  nixpkgsOverlays,
}:
let
  # A bare store path where a flake was expected. `outPath` is enough for both
  # string interpolation ("${inputs.nixpkgs}") and for the one consumer that
  # reaches for structure: `nix.registry.<name>.flake`, which reads `.outPath`
  # and optionally `.rev`/`.narHash`/`.lastModified`.
  asFlake = path: extra: { outPath = path; } // extra;

  # pkgs used to build the things Blueprint exposed under `perSystem`. Blueprint
  # built those from the flake's own nixpkgs, independent of any one host's
  # `nixpkgs.overlays`, so this mirrors that: same config and overlays the
  # top-level passes to every host, instantiated once.
  pkgs = import tamal.nixpkgs {
    inherit system;
    config = nixpkgsConfig;
    overlays = nixpkgsOverlays;
  };

  inherit (pkgs) lib;

  gitignoreSource = (import tamal.gitignore { inherit lib; }).gitignoreSource;

  # ── tsnsrv ────────────────────────────────────────────────────────────────
  # The messiest one. Upstream is flake-parts with `easyOverlay` + `partitions`,
  # and its module is `import ./nixos { flake = self; }` — it wants a whole
  # flake handed back to it. It only ever reaches two attributes out of that
  # flake (`packages.<system>.tsnsrv` and `.tsnsrvOciImage`, both as option
  # defaults), so a stub with exactly those two is enough.
  #
  # The package definition below is transcribed from tsnsrv's own `perSystem`.
  # This is the drift risk: if upstream changes how it builds, this silently
  # keeps building the old way until something breaks.
  tsnsrvPkg =
    subPackage:
    pkgs.buildGo126Module {
      pname = builtins.baseNameOf subPackage;
      version = "0.0.0";
      vendorHash = builtins.readFile "${tamal.tsnsrv}/tsnsrv.sri";
      src = lib.sourceFilesBySuffices (lib.sources.cleanSource tamal.tsnsrv) [
        ".go"
        ".mod"
        ".sum"
      ];
      subPackages = [ subPackage ];
      ldflags = [
        "-s"
        "-w"
      ];
      meta.mainProgram = builtins.baseNameOf subPackage;
    };

  tsnsrvSelf = {
    packages.${system} = {
      tsnsrv = tsnsrvPkg "cmd/tsnsrv";
      tsnsrvOciImage = pkgs.dockerTools.buildLayeredImage {
        name = "tsnsrv";
        tag = "latest";
        contents = [
          (pkgs.buildEnv {
            name = "image-root";
            paths = [ (tsnsrvPkg "cmd/tsnsrv") ];
            pathsToLink = [
              "/bin"
              "/tmp"
            ];
          })
          pkgs.dockerTools.caCertificates
        ];
        config.EntryPoint = [ "/bin/tsnsrv" ];
      };
    };
  };

  # ── micasa ────────────────────────────────────────────────────────────────
  # Its overlay shadows pkgs.govulncheck / golangci-lint / deadcode with
  # CI-wrapped variants, which is fine for micasa's own dev shell and very much
  # not fine fleet-wide. So it is applied to a scoped `pkgs.extend` used only to
  # build micasa, never to the host's package set.
  micasaPkgs = pkgs.extend (import "${tamal.micasa}/nix/overlay.nix");
  micasaPkg = micasaPkgs.callPackage "${tamal.micasa}/nix/package.nix" {
    buildGoModule = micasaPkgs.micasaBuildGoModule;
    inherit gitignoreSource;
  };

  # ── slime-chat ────────────────────────────────────────────────────────────
  slimeChatOverlay = _final: prev: {
    slime-chat = prev.callPackage "${tamal.slime-chat}/package.nix" { };
  };
in
{
  inherit pkgs;

  inputs = {
    nixpkgs = asFlake tamal.nixpkgs { };

    # `inputs.ragenix.nixosModules.default` was never ragenix's own module —
    # ragenix's flake does `inherit (agenix) nixosModules darwinModules
    # homeManagerModules`, re-exporting agenix's verbatim. Pinning agenix
    # directly says what was actually meant, and drops ragenix, crane and
    # rust-overlay from the graph. That also retires the rust-overlay `follows`
    # workaround flake.nix had been carrying.
    ragenix = asFlake tamal.agenix {
      nixosModules.default = import "${tamal.agenix}/modules/age.nix";
      darwinModules.default = import "${tamal.agenix}/modules/age.nix";
      homeManagerModules.default = import "${tamal.agenix}/modules/age-home.nix";
    };

    nix-minecraft = asFlake tamal.nix-minecraft {
      # Upstream builds this attrset with `self.lib.rakeLeaves ./modules`; the
      # directory holds exactly one file, so name it directly.
      nixosModules.minecraft-servers = import "${tamal.nix-minecraft}/modules/minecraft-servers.nix";
      overlay = import "${tamal.nix-minecraft}/overlay.nix";
      overlays.default = import "${tamal.nix-minecraft}/overlay.nix";
      lib = import "${tamal.nix-minecraft}/lib" { inherit lib; };
    };

    tsnsrv = asFlake tamal.tsnsrv {
      nixosModules.default = import "${tamal.tsnsrv}/nixos" { flake = tsnsrvSelf; };
      packages = tsnsrvSelf.packages;
    };

    micasa = asFlake tamal.micasa {
      nixosModules.default = import "${tamal.micasa}/nix/module.nix";
      packages.${system}.default = micasaPkg;
    };

    slime-chat = asFlake tamal.slime-chat {
      nixosModules.slime-chat = import "${tamal.slime-chat}/module.nix";
      nixosModules.default = {
        imports = [ (import "${tamal.slime-chat}/module.nix") ];
        nixpkgs.overlays = [ slimeChatOverlay ];
      };
      overlays.default = slimeChatOverlay;
    };

    home-manager = asFlake tamal.home-manager {
      lib = import "${tamal.home-manager}/lib" { inherit lib; };
    };
  };

  # Blueprint exposed each input's per-system packages as `perSystem.<input>`.
  # Only two are ever read, and only for one attribute each.
  perSystem = {
    # Was `perSystem.ragenix.default`, built from ragenix's flake through crane
    # + a pinned rust-overlay. nixpkgs ships the same program, so the whole
    # Rust toolchain drops out of the graph.
    ragenix.default = pkgs.ragenix;
    micasa.default = micasaPkg;
  };
}
