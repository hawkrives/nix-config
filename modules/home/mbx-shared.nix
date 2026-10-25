# mbx (jdx's Rust build tool) as the cargo frontend, backed by the remote cache
# on pantry (hosts/pantry/mbx-cache.nix).
#
# The point is disk: mbx keeps every compiled crate in one shared local store
# instead of a target/ per checkout, gc.max_size caps that store, and whatever
# gets evicted comes back from pantry instead of being recompiled.
#
# Remote settings only take effect from this global file or MBX_REMOTE_* env
# vars (a repo's .mbx.toml can't set them), so each host gets one namespace for
# everything it builds. That's deliberate: cache keys are content-addressed with
# checkout paths stripped, so one project's tokio build serves the next.
{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}: let
  cfg = config.mbx;

  # Pinned to the same release as the cache server; see flake.nix.
  mbx = perSystem.mr-boxington.mbx;

  configText = (pkgs.formats.toml {}).generate "mbx-config.toml" {
    remote = {
      url = "https://pantry.vaquita-woodpecker.ts.net";
      inherit (cfg) namespace;
      mode = "read-write";
      token_file = cfg.tokenFile;
      # mbx only uploads from protected-branch CI pushes unless told otherwise;
      # every local shell counts as read-only. This is a personal cache, and
      # without this nothing ever reaches pantry.
      trust_writes = true;
    };
    gc.max_size = cfg.maxLocalSize;
  };
in {
  options.mbx = {
    namespace = lib.mkOption {
      type = lib.types.str;
      description = "Remote cache namespace; the token in tokenFile must be granted it on pantry.";
    };
    tokenFile = lib.mkOption {
      type = lib.types.str;
      description = "Bare bearer token for pantry's mbx-cache, readable by this user.";
    };
    maxLocalSize = lib.mkOption {
      type = lib.types.str;
      default = "10GiB";
      description = "Cap on the local mbx action store (mbx's own default is 5% of the disk).";
    };
  };

  config = lib.mkMerge [
    {
      # mbx from Nix rather than mise: mise only installs mbx's prebuilt glibc
      # binary, which NixOS can't run without nix-ld.
      home.packages = [mbx];

      # Plain `cargo build` goes through mbx: libexec/mbx/cargo is upstream's
      # shim, which finds the real cargo (rustup's, from home-shared) further
      # down PATH and runs it under mbx. mkBefore keeps it ahead of everything
      # else this config adds to PATH.
      home.sessionPath = lib.mkBefore ["${mbx}/libexec/mbx"];
    }
    # mbx reads its global config from the platform config dir, which on macOS
    # is not XDG.
    (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      home.file."Library/Application Support/mbx/config.toml".source = configText;
    })
    (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      xdg.configFile."mbx/config.toml".source = configText;
    })
  ];
}
