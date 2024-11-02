{ unstable-pkgs }:

{ pkgs, config, ... }:

{
  imports = [ ../../common/users/shared.nix ];

  home.packages = with pkgs; [
    atuin
    awscli
    bacon
    bartib
    bat
    broot
    colima
    curl
    delta
    difftastic
    direnv
    dive
    dog
    entr
    eza
    fd
    ffmpeg
    fish
    fx # tui json viewer
    fzf
    gh
    git
    git-absorb
    glab # gitlab cli
    graphviz
    gron
    helix
    htmlq
    htop
    hyperfine
    imagemagick
    jless
    jq
    lazydocker
    lazygit
    lima
    lnav
    mariadb
    mise
    mosh
    unstable-pkgs.nixos-generators
    nushell
    parallel
    procs
    pstree
    pv
    python3
    readline
    ripgrep
    rlwrap
    rustup
    shellcheck
    sqlite
    tmux
    tokei
    tree
    trippy
    unstable-pkgs.go
    unstable-pkgs.jujutsu
    unstable-pkgs.neovim
    visidata
    watch
    wget
    xh
    xsv
    xz
    yq
    yt-dlp
    zellij
    zstd
  ];

  programs.git = {
    enable = true;
    aliases = {
      co = "checkout";
      st = "status";
      ci = "commit";
      br = "branch";
    };
    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
    };
  };

  home.sessionPath =
    [ "$HOME/go/bin" "$HOME/bin" "$HOME/.local/bin" ];
}
