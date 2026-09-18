# The prebuilt macOS mise binary, fetched from the same place the official
# `curl https://mise.run | sh` installer gets it (mise.jdx.dev).
#
# macOS uses this instead of the nixpkgs mise, which trails upstream releases.
# Building mise from source is no alternative: upstream's own flake fails its
# test suite in the darwin sandbox.
#
# Renovate bumps `tag` and `sha256` together (see renovate.json5), taking the
# new checksum from the release's SHASUMS256.txt. By hand: set `tag`, then copy
# the macos-arm64 `.tar.gz` checksum from https://mise.run.
#
# Only aarch64-darwin: nixpkgs has dropped x86_64-darwin.
{ pkgs, ... }:
let
  inherit (pkgs)
    lib
    stdenvNoCC
    fetchurl
    installShellFiles
    ;

  # The tag must sit directly above the sha256 of the macos-arm64 .tar.gz:
  # Renovate's regex in renovate.json5 matches the pair.
  # renovate: datasource=github-release-attachments depName=jdx/mise
  tag = "v2026.9.11";
  sha256 = "34e8296f932c1d6f3b84d924bbb9f2841336d7bee1c373005d479e13664cb6c0";

  version = lib.removePrefix "v" tag;
in
stdenvNoCC.mkDerivation {
  pname = "mise-bin";
  inherit version;

  src = fetchurl {
    url = "https://mise.jdx.dev/${tag}/mise-${tag}-macos-arm64.tar.gz";
    inherit sha256;
  };

  nativeBuildInputs = [ installShellFiles ];

  # The tarball also carries a fish vendor_conf.d script that activates mise.
  # It is left out on purpose: home-manager's programs.mise already does that.
  installPhase = ''
    runHook preInstall
    install -Dm755 bin/mise $out/bin/mise
    installManPage man/man1/mise.1
    runHook postInstall
  '';

  meta = {
    description = "Dev tools, env vars, and tasks in one CLI (prebuilt release binary)";
    homepage = "https://mise.jdx.dev";
    license = lib.licenses.mit;
    mainProgram = "mise";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
