{ username, hostname }:
{ config, pkgs, ... }:
{
  imports = [ ../../common/hosts/darwin.nix ];

  nix.settings.trusted-users = [
    "root"
    username
  ];

  networking.hostName = hostname;
  networking.computerName = hostname;

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

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  system.keyboard.remapCapsLockToEscape = true;

  environment.systemPackages = with pkgs; [
    amazon-ecr-credential-helper
    nix-output-monitor
    nh
  ];

  homebrew = {
    enable = true;
    onActivation = {
      # autoUpdate = true;
      # upgrade = true;
      cleanup = "zap";
    };

    taps = [
      "homebrew/cask-fonts"
    ];

    brews = [
      "container-diff"
    ];

    caskArgs.appdir = "~/Applications";
    casks = [
      "font-blex-mono-nerd-font"
      "anytype"
      "arc"
      "bbedit"
      "bike"
      "docker"
      "firefox"
      "firefox@nightly"
      "gitup"
      "google-chrome"
      "handbrake"
      "iterm2"
      "jetbrains-toolbox"
      "kaleidoscope"
      "mimestream"
      "mullvadvpn"
      "nova"
      "plexamp"
      "remote-desktop-manager"
      "sublime-merge"
      "sublime-text"
      "telegram-desktop"
      "thunderbird"
      "visual-studio-code"
      "vlc"
      "wezterm"
      "yattee"
      "zed"
    ];

    masApps = {
      "Acorn 7" = 1547371478;
      "AWS Extend Switch Roles" = 1592710340;
      # "Bike Outliner" = 1588292384;
      "iA Writer" = 775737590;
      "Keynote" = 409183694;
      "Lungo" = 1263070803; # caffeine
      # "Notchmeister" = 1599169747;
      "Numbers" = 409203825;
      "Pages" = 409201541;
      "Paste" = 967805235;
      "Photomator" = 1444636541;
      "Pixelmator" = 1289583905;
      "Tailscale" = 1475387142;
      "The Unarchiver" = 425424353;
      "WireGuard" = 1451685025;
    };
  };

  users.users.${username} = {
    name = "${username}";
    home = "/Users/${username}";
    shell = pkgs.fish;
  };
}
