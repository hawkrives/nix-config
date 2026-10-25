# adguardhome-sync: copies one AdGuard Home's settings (filters, rewrites,
# clients, ...) to replicas through their web APIs. Not in nixpkgs. Runs on
# potato-bunny to keep the second AdGuard in step with nutmeg's
# (hosts/potato-bunny/adguard.nix). To bump: set `version`, blank both hashes,
# build, and paste in the hashes nix reports.
{pkgs, ...}: let
  inherit (pkgs) lib buildGo127Module fetchFromGitHub;
in
  # go.mod requires Go 1.27.
  buildGo127Module rec {
    pname = "adguardhome-sync";
    version = "0.9.5";

    src = fetchFromGitHub {
      owner = "bakito";
      repo = "adguardhome-sync";
      tag = "v${version}";
      hash = "sha256-tlntcz7L8Ky1hrzlLMFZp+VPEoFI8JtD0V4/UTu4Q+g=";
    };

    vendorHash = "sha256-aR3ciz7KsQaxn+m86ZxTdbwWCVdyJy0tTunSPJJ0afs=";

    ldflags = [
      "-s"
      "-w"
      "-X github.com/bakito/adguardhome-sync/version.Version=${version}"
    ];

    # The tests start mock AdGuard servers and need the network.
    doCheck = false;

    meta = {
      description = "Synchronize AdGuard Home config to replicas";
      homepage = "https://github.com/bakito/adguardhome-sync";
      license = lib.licenses.asl20;
      mainProgram = "adguardhome-sync";
      platforms = lib.platforms.linux;
    };
  }
