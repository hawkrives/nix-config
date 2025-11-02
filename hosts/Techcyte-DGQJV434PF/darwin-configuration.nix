{
  inputs,
  pkgs,
  pkgsUnstable,
  hostName,
  flake,
  ...
}: {
  imports = [
    flake.modules.common.nixpkgs-unstable # provides the pkgsUnstable argument

    inputs.self.nixosModules.host-shared
    inputs.self.darwinModules.host-shared
    # inputs.nix-rosetta-builder.darwinModules.default
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  system.primaryUser = "hawken.rives";
  users.users."hawken.rives" = {
    home = /Users/hawken.rives;
    shell = pkgs.fish;
    packages = [
      pkgs.awscli2
      pkgsUnstable.copilot-cli
    ];
  };

  # @admin is required for nix-builder
  nix.settings.trusted-users = ["root" "@admin"];
  # nix.settings.substituters = ["https://attic.services.hub.techcyte.com/cache"];
  nix.settings.netrc-file = "/Users/hawken.rives/.netrc"; # string, not path, to avoid copying into the nix store
  nix.settings.extra-sandbox-paths = ["/Users/hawken.rives/.netrc"];

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
  system.defaults.smb.NetBIOSName = hostName;

  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = true;

  # disable the startup chime
  system.startup.chime = false;

  environment.systemPackages = [
    pkgs.amazon-ecr-credential-helper
    pkgsUnstable.attic-client
    pkgsUnstable.nil # for nix lsp for vs code / zed
    pkgsUnstable.devenv
  ];

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "zap";
    };

    # container-diff has been replaced with diffoci
    brews = [];

    caskArgs.appdir = "~/Applications";
    casks = [
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

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
