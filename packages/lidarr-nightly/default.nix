# Lidarr built from a pre-release tag, for plugin support (System → Plugins).
#
# nixpkgs packages Lidarr's stable channel, which is still 3.1.0 — a version
# with no plugin loader. Plugins arrived in the 3.1.3+ pre-releases, and the
# Tubifarry plugin (slskd as a Lidarr indexer + download client) needs at
# least 3.1.6.0. This is nixpkgs' pkgs/by-name/li/lidarr/package.nix with the
# version bumped and its own NuGet lock file; delete it and go back to
# `pkgs.lidarr` once nixpkgs' stable Lidarr is at or past this version.
#
# Upgrading Lidarr migrates its database one way: never point the service back
# at an older build than this without restoring a backup.
#
# To bump: set `version`, swap both hashes for lib.fakeHash and build to get the
# real ones, then regenerate deps.json on an x86_64-linux host with
#   nix build .#lidarr-nightly.fetch-deps && ./result packages/lidarr-nightly/deps.json
{pkgs, ...}: let
  inherit
    (pkgs)
    lib
    stdenvNoCC
    fetchFromGitHub
    buildDotnetModule
    dotnetCorePackages
    sqlite
    fetchYarnDeps
    yarn
    fixup-yarn-lock
    nodejs
    prefetch-yarn-deps
    applyPatches
    ;

  version = "3.1.6.5078";
  src = applyPatches {
    src = fetchFromGitHub {
      owner = "Lidarr";
      repo = "Lidarr";
      tag = "v${version}";
      hash = "sha256-vazxW5aYlUjXo2SNSyspc+hk1HoLHI0brbm7e/qSrk0=";
    };
    postPatch = ''
      mv src/NuGet.config NuGet.Config
    '';
  };
  rid = dotnetCorePackages.systemToDotnetRid stdenvNoCC.hostPlatform.system;
in
  buildDotnetModule {
    pname = "lidarr";
    inherit version src;

    strictDeps = true;
    nativeBuildInputs = [
      nodejs
      yarn
      prefetch-yarn-deps
      fixup-yarn-lock
    ];

    yarnOfflineCache = fetchYarnDeps {
      yarnLock = "${src}/yarn.lock";
      hash = "sha256-Jq2O7gvB+PKcz6uDBMg7ox6/Bu+pikXH6JGuLfKG5fI=";
    };

    postConfigure = ''
      yarn config --offline set yarn-offline-mirror "$yarnOfflineCache"
      fixup-yarn-lock yarn.lock
      yarn install --offline --frozen-lockfile --ignore-platform --ignore-scripts --no-progress --non-interactive
      patchShebangs --build node_modules
    '';
    postBuild = ''
      yarn --offline run build --env production
    '';
    postInstall = ''
      cp -a -- _output/UI "$out/lib/lidarr/UI"
    '';

    nugetDeps = ./deps.json;

    runtimeDeps = [sqlite];

    dotnet-sdk = dotnetCorePackages.sdk_8_0;
    dotnet-runtime = dotnetCorePackages.aspnetcore_8_0;

    # nixpkgs runs Lidarr's test suite against the stable release, with a list of
    # tests that need filtering out; a pre-release can break that list, and the
    # tests were already run upstream before the tag was cut.
    doCheck = false;

    __structuredAttrs = true; # for Copyright property that contains spaces

    executables = ["Lidarr"];

    projectFile = [
      "src/NzbDrone.Console/Lidarr.Console.csproj"
      "src/NzbDrone.Mono/Lidarr.Mono.csproj"
    ];

    dotnetFlags = [
      "--property:TargetFramework=net8.0"
      "--property:EnableAnalyzers=false"
      "--property:SentryUploadSymbols=false" # Fix Sentry upload failed warnings
      # Override defaults in src/Directory.Build.props that use current time.
      "--property:Copyright=Copyright 2014-2026 lidarr.audio (GNU General Public v3)"
      "--property:AssemblyVersion=${version}"
      "--property:AssemblyConfiguration=develop"
      "--property:RuntimeIdentifier=${rid}"
    ];

    meta = {
      description = "Usenet/BitTorrent music downloader (pre-release, with plugin support)";
      homepage = "https://lidarr.audio";
      changelog = "https://github.com/Lidarr/Lidarr/releases/tag/v${version}";
      license = lib.licenses.gpl3Only;
      mainProgram = "Lidarr";
      platforms = ["x86_64-linux"];
    };
  }
