# The prebuilt macOS agentsview binary from the project's GitHub releases.
# Upstream is a Go server with an embedded Svelte frontend; it is not in
# nixpkgs and has no flake.
#
# Renovate bumps `tag` and `sha256` together (see renovate.json5). By hand: set
# `tag`, then hash `agentsview_<version>_darwin_arm64.tar.gz` from the release.
#
# Only aarch64-darwin: nixpkgs has dropped x86_64-darwin.
{ pkgs, ... }:
let
  inherit (pkgs) lib stdenvNoCC fetchurl;

  # The tag must sit directly above the sha256 of the darwin_arm64 .tar.gz:
  # Renovate's regex in renovate.json5 matches the pair.
  # renovate: datasource=github-release-attachments depName=wesm/agentsview
  tag = "v0.45.0";
  sha256 = "c2b5a24d4fc4455a656c54f16b0e281f894c648f8a039fa52e76a47e1e18315b";

  version = lib.removePrefix "v" tag;
in
stdenvNoCC.mkDerivation {
  pname = "agentsview";
  inherit version;

  src = fetchurl {
    url = "https://github.com/wesm/agentsview/releases/download/${tag}/agentsview_${version}_darwin_arm64.tar.gz";
    inherit sha256;
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 agentsview $out/bin/agentsview
    runHook postInstall
  '';

  meta = {
    description = "Browse and search AI coding agent sessions (prebuilt release binary)";
    homepage = "https://github.com/wesm/agentsview";
    license = lib.licenses.mit;
    mainProgram = "agentsview";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
