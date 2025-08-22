{
  inputs,
  pkgs,
  hostName,
  ...
}: let
  username = "hawken.rives";
  # TODO: fix
  hostname = hostName;
in {
  imports = [
    inputs.self.nixosModules.host-shared
    inputs.self.darwinModules.host-shared
  ];

  boot.binfmt.emulatedSystems = ["x86_64-linux"];

  nixpkgs.hostPlatform = "aarch64-darwin";

  users.users.${username}.home = /Users/hawken.rives;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;

  # @admin is required for nix-builder
  nix.settings.trusted-users = [
    "root"
    username
    "@admin"
  ];
  nix.settings.substituters = [
    "https://attic.services.hub.techcyte.com/cache"
    "https://cache.nixos.org"
    "https://cache.lix.systems"
  ];
  nix.settings.trusted-public-keys = [
    "cache:fWnI+McRUwqFqvEzDFkCOU256xHHztm+SR1l2UWGZzU="
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
  ];
  nix.settings.netrc-file = "/Users/${username}/.netrc";

  # https://nixcademy.com/posts/macos-linux-builder/
  # TODO: do we still want this? I saw something about setting binfmt...?
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
    dock.autohide = true;
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

  system.keyboard.remapCapsLockToEscape = true;

  environment.systemPackages = [
    pkgs.amazon-ecr-credential-helper
    inputs.unstable-pkgs.attic-client
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
      "d12frosted/homebrew-emacs-plus" # for emacs-plus
    ];

    brews = [
      "container-diff"
      {
        name = "emacs-plus";
        args = [
          "with-savchenkovaleriy-big-sur-3d-icon"
          "with-no-frame-refocus"
          "with-native-comp"
        ];
      }
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
      "Muse" = 1501563902;
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

  # TODO: home-manager
  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    shell = pkgs.fish;
  };
}
