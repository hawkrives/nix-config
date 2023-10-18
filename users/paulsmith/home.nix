{ pkgs, ... }: {
  # The state version is required and should stay at the version you
  # originally installed.
  home.stateVersion = "23.05";

  home.packages = with pkgs; [
    awscli
    bat
    direnv
    ffmpeg
    fx
    fzf
    gh
    git
    helix
    htop
    imagemagick
    jq
    mosh
    pv
    ripgrep
    rlwrap
    sqlite
    swig
    tree
  ];

  programs.home-manager.enable = true;

  programs.bash = {
    enable = true;
    historyControl = [ "ignoredups" "ignorespace" ];
    shellAliases = {
      ls = "ls --color=auto";
      ll = "ls -l";
    };
    initExtra = ''
export PS1="\[\e[1;34m\]\W\[\e[0m\] \[\e[1;33m\]\$\[\e[0m\] "
'';
  };

  programs.git = {
    enable = true;
    userName = "Paul Smith";
    userEmail = "paul@adhocteam.us";
    aliases = {
      co = "checkout";
      st = "status";
      ci = "commit";
      br = "branch";
    };
    extraConfig = {
      init = { defaultBranch = "main"; };
      push = { autoSetupRemote = true; };
    };
  };

  programs.dircolors.enable = true;
  programs.direnv.enable = true;

  imports = [
    ./vim.nix
  ];
}
