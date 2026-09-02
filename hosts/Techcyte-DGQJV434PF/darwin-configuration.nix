{
  inputs,
  pkgs,
  hostName,
  ...
}: let
  # Its own directory, not age.secretsDir: this whole directory is handed to
  # the linux-builder VM over virtiofs, and age.secretsDir holds every other
  # secret on this host.
  builderNetrcDir = "/run/nix-builder";
in {
  imports = [
    inputs.self.nixosModules.host-shared
    inputs.self.darwinModules.host-shared
    inputs.self.nixosModules.cache-push
    # Deliberately NOT pantry-builder. This host has its own linux-builder VM
    # (below), and with both registered Lix sent nearly everything to pantry:
    # when two builders are idle it breaks the tie on speedFactor alone, and
    # pantry declares 2 against the nix-darwin default of 1. Even with that
    # corrected an idle pantry would still win whenever the local VM had a job
    # running (load/speedFactor, and 0 beats every positive value), so the only
    # way to actually keep builds on the M-series is to not offer the
    # alternative. Building x86_64-linux locally under Rosetta beats shipping it
    # to a 4-core V1500B over the tailnet.
    # inputs.nix-rosetta-builder.darwinModules.default
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  system.primaryUser = "hawken.rives";
  users.users."hawken.rives" = {
    home = /Users/hawken.rives;
    shell = pkgs.fish;
  };

  # @admin is required for nix-builder
  nix.settings.trusted-users = ["root" "@admin"];
  # nix.settings.substituters = ["https://attic.services.hub.techcyte.com/cache"];
  nix.settings.netrc-file = "/Users/hawken.rives/.netrc"; # string, not path, to avoid copying into the nix store
  nix.settings.extra-sandbox-paths = ["/Users/hawken.rives/.netrc"];

  # Decrypted outside age.secretsDir so the linux-builder VM can be given this
  # directory without being given every other secret. 0444 because the guest
  # reads it as a different uid across virtiofs.
  age.secrets.builder-netrc = {
    file = ../../secrets/builder-netrc.age;
    path = "${builderNetrcDir}/netrc";
    mode = "0444";
    # agenix defaults to writing the real file into age.secretsDir and
    # symlinking `path` at it. That link is what the VM would mount, and it
    # points somewhere the guest has no equivalent of — a dangling link and a
    # silent 401. Write the file itself here instead.
    symlink = false;
  };

  nix.linux-builder = {
    enable = true;

    package = pkgs.darwin.linux-builder-vz;
    # Deliberately no i686-linux. This guest is aarch64-linux and serves
    # x86_64-linux through Rosetta, which emulates 64-bit x86 only — listing
    # i686-linux advertises a capability it does not have, so builds are
    # dispatched here and then refused with "platform mismatch" instead of
    # failing early with something legible.
    systems = [ "aarch64-linux" "x86_64-linux" ];

    # Performance/tuning settings
    ephemeral = true;
    maxJobs = 6;
    config = {
      # Nix's sandbox build directory (/build inside the sandbox) is a bind
      # mount backed by `build-dir` on the host, default /nix/var/nix/b. This
      # VM's "/" is deliberately tmpfs (vz-vm.nix, for fast ephemeral boot), so
      # that default location lands on RAM, capped at the kernel's default
      # tmpfs sizing (50% of VM memory) regardless of disk size. Point it at
      # /nix/.rw-store instead, which is real, disk-backed storage (/dev/vdb,
      # sized via diskSize below). Lix creates this directory itself if missing
      # (man nix.conf).
      nix.extraOptions = "build-dir = /nix/.rw-store/nix-build-dir\n";

      virtualisation = {
        vz.nestedVirtualization = true;
        darwin-builder = {
          # TensorRT alone needs ~30GB at peak: a 6.4GB tarball in the store,
          # 10.7GB unpacked, and a ~10GB install output, on top of its CUDA
          # build inputs. The image builds carrying that stack plus cuDNN and
          # the CUDA runtime want similar headroom. This is only useful
          # together with build-dir above, which is what actually puts build
          # scratch on this disk.
          diskSize = 150 * 1024;
          memorySize = 16 * 1024;
        };
        cores = 8;

        # The host's netrc-file setting is local-daemon config and is not
        # forwarded over ssh-ng, so a derivation built here cannot authenticate
        # its fixed-output fetches. Anything targeting x86_64-linux from this
        # aarch64-darwin host builds here — including the wheel fetches for
        # Techcyte's private GitLab package index, which 401 without this.
        #
        # A virtiofs share is a directory, so this shares the dedicated
        # directory agenix decrypts builder-netrc into — deliberately NOT
        # age.secretsDir, which holds every other secret on this host.
        #
        # Mounted under /var/lib, not /etc: NixOS assembles /etc during
        # activation, so a mountpoint it does not know about is not there for
        # systemd to mount onto, and the share silently never appears. The only
        # /etc share in the VM modules targets /etc/ssl/certs, which NixOS
        # creates itself.
        sharedDirectories.netrc = {
          source = builderNetrcDir;
          target = "/var/lib/nix-builder";
        };
      };

      # netrc-file covers Nix's own downloads: substituters, flake inputs,
      # builtins.fetchurl.
      nix.settings.netrc-file = "/var/lib/nix-builder/netrc";

      # It does NOT cover nixpkgs' fetchurl, which runs curl inside the build
      # sandbox and only passes --netrc-file when the caller supplies a
      # netrcPhase. uv2nix calls fetchurl bare, so the wheels from Techcyte's
      # private GitLab index 401 no matter what netrc-file says. fetchurl
      # declares NIX_CURL_FLAGS as an impure env var precisely for this, and
      # the sandbox needs the file itself on its allowed paths.
      nix.settings.extra-sandbox-paths = [ "/var/lib/nix-builder/netrc" ];
      systemd.services.nix-daemon.environment.NIX_CURL_FLAGS =
        "--netrc-file /var/lib/nix-builder/netrc";
    };
  };

  # something went wrong during setup and this is 350 instead of 30000
  ids.gids.nixbld = 350;

  networking.hostName = hostName;
  networking.computerName = hostName;
  # NetBIOSName is deliberately unset. Writing it needs Full Disk Access, and
  # without that macOS refuses the write and aborts activation before it
  # finishes — silently leaving a switch half-applied. Nothing here shares
  # files to Windows, so the name is not worth that failure mode.

  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = true;

  # disable the startup chime
  system.startup.chime = false;

  environment.systemPackages = [
    pkgs.amazon-ecr-credential-helper
    # pkgs.attic-client
    pkgs.nil # for nix lsp for vs code / zed
    # pkgs.devenv
    # pkgs.colima
    pkgs.mas
    # macos apps
    # pkgs.jetbrains.datagrip
    # pkgs.jetbrains.goland
  ];

  homebrew = {
    # enable = true;
    enable = false;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
    };

    caskArgs.appdir = "~/Applications";
    casks = [
      "alfred"
      "anytype"
      "bbedit"
      "bike"
      "docker-desktop"
      "element"
      "expo-orbit"
      "firefox"
      "ghostty"
      "gitup-app"
      "google-chrome"
      "handbrake-app"
      "kaleidoscope"
      "keepingyouawake"
      "mimestream"
      "mullvad-vpn"
      "nova"
      "obs"
      "plexamp"
      "sublime-merge"
      "sublime-text"
      "tailscale-app"
      "visual-studio-code"
      "virtualbuddy"
      "vlc"
      "zed"
    ];

    masApps = {
      # "Acorn 7" = 1547371478;
      "iA Writer" = 775737590;
      "Muse" = 1501563902;
      "Nautik" = 1672838783;
      "Photomator" = 1444636541;
      "Pixelmator" = 1289583905;
      "Soulver 3" = 1508732804;
      "The Unarchiver" = 425424353;
      "Things" = 904280696;
      "Wipr 2" = 1662217862;
      "WireGuard" = 1451685025;
      "Xcode" = 497799835;
    };
  };

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
