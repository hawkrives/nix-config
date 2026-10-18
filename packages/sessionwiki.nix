# The prebuilt macOS sessionwiki binary from the project's GitHub releases.
# Upstream is a Rust CLI that is not in nixpkgs and has no flake.
#
# Renovate bumps `tag` and `sha256` together (see renovate.json5). By hand: set
# `tag`, then copy the checksum from the release's
# `sessionwiki-<tag>-aarch64-apple-darwin.tar.gz.sha256`.
#
# Only aarch64-darwin: nixpkgs has dropped x86_64-darwin.
{pkgs, ...}: let
  inherit (pkgs) lib stdenvNoCC fetchurl;

  # The tag must sit directly above the sha256 of the aarch64-apple-darwin
  # .tar.gz: Renovate's regex in renovate.json5 matches the pair.
  # renovate: datasource=github-release-attachments depName=youdie006/sessionwiki
  tag = "v0.34.3";
  sha256 = "5c1f47ecf28ec0e5a7c75be54d7b33155d2949741872613a40f4998874bda476";

  version = lib.removePrefix "v" tag;
in
  stdenvNoCC.mkDerivation {
    pname = "sessionwiki";
    inherit version;

    src = fetchurl {
      url = "https://github.com/youdie006/sessionwiki/releases/download/${tag}/sessionwiki-${tag}-aarch64-apple-darwin.tar.gz";
      inherit sha256;
    };

    installPhase = ''
      runHook preInstall
      install -Dm755 sessionwiki $out/bin/sessionwiki
      runHook postInstall
    '';

    meta = {
      description = "Local search over AI coding session history (prebuilt release binary)";
      homepage = "https://github.com/youdie006/sessionwiki";
      license = lib.licenses.mit;
      mainProgram = "sessionwiki";
      platforms = ["aarch64-darwin"];
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
