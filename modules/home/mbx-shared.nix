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
  ...
}: let
  cfg = config.mbx;

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
      # mise routes cargo through mbx via the rust tool's mr_boxington option, so
      # plain `cargo build` keeps working. mise's rust backend drives rustup
      # (home-shared) for the toolchain itself.
      programs.mise.globalConfig.tools = {
        # Pinned so it moves together with the server (packages/mbx-cache.nix):
        # both sides of the cache protocol are experimental.
        mr-boxington = "1.27.0";
        rust = {
          version = "stable";
          mr_boxington = true;
        };
      };
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
