{
  # inputs,
  flake,
  pkgs,
  hostName,
  perSystem,
  ...
}: let
  username = "hawken.rives";
in {
  imports = [
    flake.nixosModules.host-shared
    flake.darwinModules.host-shared
    # inputs.nix-rosetta-builder.darwinModules.default
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;

  users.users.${username} = {
    name = username;
    home = /Users/${username};
    shell = pkgs.fish;
  };

  # @admin is required for nix-builder
  nix.settings.trusted-users = [
    "root"
    username
    "@admin"
  ];
  nix.settings.substituters = [
    # "https://attic.services.hub.techcyte.com/cache"
    "https://cache.nixos.org"
    "https://cache.lix.systems"
    "https://nix-community.cachix.org"
  ];
  nix.settings.trusted-public-keys = [
    "cache:fWnI+McRUwqFqvEzDFkCOU256xHHztm+SR1l2UWGZzU="
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cache.lix.systems:aBnZUw8zA7H35Cz2RyKFVs3H4PlGTLawyY5KRbvJR8o="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];
  nix.settings.netrc-file = "/Users/${username}/.netrc";

  # https://nixcademy.com/posts/macos-linux-builder/
  # but then... https://github.com/cpick/nix-rosetta-builder
  # nix.linux-builder = {
  #   enable = false;
  # };
  # nix-rosetta-builder = {
  #   onDemand = true;
  #   onDemandLingerMinutes = 10;
  #   diskSize = "60GiB";
  # };

  # something went wrong during setup and this is 350 instead of 30000
  ids.gids.nixbld = 350;

  networking.hostName = hostName;
  networking.computerName = hostName;

  system.primaryUser = username;

  system.defaults = {
    dock.autohide = true;
    dock.mru-spaces = false;
    dock.mouse-over-hilite-stack = true;
    dock.showhidden = true;
    dock.slow-motion-allowed = false;

    smb.NetBIOSName = hostName;
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
  system.keyboard.remapCapsLockToEscape = true;

  # disable the startup chime
  system.startup.chime = false;

  environment.systemPackages = [
    pkgs.amazon-ecr-credential-helper
    perSystem.nixpkgs-unstable.attic-client
    perSystem.nixpkgs-unstable.nil # for nix lsp for vs code
    pkgs.devenv
  ];

  homebrew = {
    enable = true;
    onActivation = {
      # autoUpdate = true;
      # upgrade = true;
      cleanup = "zap";
    };

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
}
