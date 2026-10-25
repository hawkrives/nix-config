# mbx-cache: the reference remote build-cache server for mbx (jdx's Rust build
# tool) and mise's task cache. Not in nixpkgs, no flake, and the crates.io
# `mbx-cache` crate is an empty placeholder, so this builds from a pinned commit.
#
# Pinned to a commit rather than a tag: the tags trail main by a protocol
# version. Keep this roughly in step with the mbx client — the protocol is v1
# but both projects are experimental. To bump: set `rev` and `date`, blank both
# hashes, build, and paste in the hashes nix reports.
{pkgs, ...}: let
  inherit (pkgs) lib rustPlatform fetchFromGitHub;

  rev = "b6140dae7ae06a5efb52e9cd438f08c8bae48a8e";
  date = "2026-10-23";
in
  rustPlatform.buildRustPackage {
    pname = "mbx-cache";
    version = "0.2.0-unstable-${date}";

    src = fetchFromGitHub {
      owner = "jdx";
      repo = "mr-boxington-cache";
      inherit rev;
      hash = "sha256-KhlNMCjNliXdqvXu6zzCGPrE+kzDscW5j+46BuYKs0g=";
    };

    cargoHash = "sha256-48KALMCfoWY/c2wuvJpE17U8PzrCxgDUpG4T45QME5o=";

    # Exported as a label on the /metrics build-info gauge.
    env.MBX_CACHE_BUILD_REVISION = rev;

    # The suite's postgres tests want a live database.
    doCheck = false;

    meta = {
      description = "Self-hosted remote build cache server for mbx";
      homepage = "https://github.com/jdx/mr-boxington-cache";
      license = lib.licenses.mit;
      mainProgram = "mbx-cache";
      platforms = lib.platforms.linux;
    };
  }
