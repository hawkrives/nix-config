{ username, hostname, unstable-pkgs }:
{ config, pkgs, ... }: {
  imports = [ ../../common/hosts/darwin.nix ];

  # @admin is required for nix-builder
  nix.settings.trusted-users = [ "root" username "@admin" ];
  nix.settings.substituters = ["https://attic.services.hub.techcyte.com/cache" "https://cache.nixos.org"];
  nix.settings.trusted-public-keys = ["cache:fWnI+McRUwqFqvEzDFkCOU256xHHztm+SR1l2UWGZzU=" "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="];
  nix.settings.netrc-file = "/Users/${username}/.netrc";
  # https://nixcademy.com/posts/macos-linux-builder/
  nix.linux-builder = {
    enable = true;
    ephemeral = true;
    maxJobs = 4;
    config = {
      virtualisation = {
        darwin-builder = {
          diskSize = 40 * 1024;
          memorySize = 8 * 1024;
        };
        cores = 6;
      };
    };
  };

  # something went wrong during setup and this is 350 instead of 30000
  ids.gids.nixbld = 350;

  networking.hostName = hostname;
  networking.computerName = hostname;

  system.primaryUser = username;

  system.defaults = {
    dock.autohide = false;
    dock.mru-spaces = false;
    dock.mouse-over-hilite-stack = true;
    dock.showhidden = true;
    dock.slow-motion-allowed = false;

    smb.NetBIOSName = hostname;
    # screencapture.location = "~/Pictures/screenshots";
    screencapture.disable-shadow = true;

    finder.ShowPathbar = true;
    finder.ShowStatusBar = true;

    menuExtraClock.Show24Hour = true;
    menuExtraClock.ShowAMPM = false;

    # Use scroll gesture with the Ctrl (^) modifier key to zoom. The default is false.
    # universalaccess.closeViewScrollWheelToggle = true;
    # universalaccess.reduceMotion = true;
  };

  system.keyboard.enableKeyMapping = true;

  # disable the startup chime
  system.startup.chime = false;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  system.keyboard.remapCapsLockToEscape = true;

  environment.systemPackages = with pkgs; [
    amazon-ecr-credential-helper
    nix-output-monitor
    nh
    unstable-pkgs.attic-client
    unstable-pkgs.devenv
  ];



  homebrew = {
    enable = true;
    onActivation = {
      # autoUpdate = true;
      # upgrade = true;
      cleanup = "zap";
    };

    taps = [
      # "homebrew/cask-fonts"
    ];

    brews = [
      "container-diff"
    ];

    caskArgs.appdir = "~/Applications";
    casks = [
      "font-blex-mono-nerd-font"
      "alfred"
      "anytype"
      "bbedit"
      "bike"
      "docker-desktop"
      "firefox"
      "ghostty"
      "gitup-app"
      "google-chrome"
      "handbrake-app"
      "jetbrains-toolbox"
      "kaleidoscope"
      "keepingyouawake"
      "mimestream"
      "mullvad-vpn"
      "nova"
      "obs"
      "obs-backgroundremoval"
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
      "AWS Extend Switch Roles" = 1592710340;
      "iA Writer" = 775737590;
      "Keynote" = 409183694;
      "Nautik" = 1672838783;
      "Numbers" = 409203825;
      "Pages" = 409201541;
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

  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    shell = pkgs.fish;
  };
}
