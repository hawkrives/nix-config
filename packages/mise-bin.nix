# The prebuilt macOS mise binary, fetched from the same place the official
# `curl https://mise.run | sh` installer gets it (mise.jdx.dev).
#
# macOS uses this instead of the nixpkgs mise, which trails upstream releases.
# Building mise from source is no alternative: upstream's own flake fails its
# test suite in the darwin sandbox.
#
# To bump: set `version`, then copy the macos-arm64 and macos-x64 `.tar.gz`
# checksums from https://mise.run (convert with `nix hash to-sri --type sha256`).
{ pkgs, ... }:
let
  inherit (pkgs)
    lib
    stdenvNoCC
    fetchurl
    installShellFiles
    ;

  version = "2026.9.11";

  # mise's name for each platform, and the sha256 of its tarball
  platforms = {
    aarch64-darwin = {
      arch = "arm64";
      hash = "sha256-NOgpb5MsHW87hNkku7nyhBM2177hw3MAXUeeE2ZMtsA=";
    };
    x86_64-darwin = {
      arch = "x64";
      hash = "sha256-RqZ7BQ1T8e55U1P4/17P15MoofZBX0s+3nns2nIj+Wk=";
    };
  };

  platform =
    platforms.${stdenvNoCC.hostPlatform.system}
      or (throw "mise-bin: no prebuilt mise for ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "mise-bin";
  inherit version;

  src = fetchurl {
    url = "https://mise.jdx.dev/v${version}/mise-v${version}-macos-${platform.arch}.tar.gz";
    inherit (platform) hash;
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
    platforms = builtins.attrNames platforms;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
