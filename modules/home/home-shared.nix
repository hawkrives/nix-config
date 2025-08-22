{
  pkgs,
  osConfig,
  perSystem,
  ...
}: {
  programs.fish.enable = true;

  # enable the nice fish prompt
  programs.fish.plugins = [
    {
      name = "pure";
      src = pkgs.fishPlugins.pure.src;
    }
  ];

  # only available on linux, disabled on macos
  services.ssh-agent.enable = pkgs.stdenv.isLinux;

  # TODO: relocate this
  home.shellAliases = {
    ls = "ls --color=auto";
    ll = "ls -l";
    view = "nvim -R";
    vimdiff = "nvim -d";
    gs = "git status";
    gd = "git diff";
    gdc = "git diff --cached";
  };

  # TODO: relocate this
  home.sessionPath = [
    "$HOME/.cargo/bin"
    "$HOME/go/bin"
    "$HOME/bin"
    "$HOME/.local/bin"
    "/opt/homebrew/bin"
  ];

  # TODO: do we want these?
  programs.dircolors.enable = true;
  programs.direnv.enable = true;

  home.packages =
    [
      perSystem.alejandra.default # nix formatter
      perSystem.nil.nil # nix lsp

      perSystem.nixpkgs-unstable.ghostty.terminfo

      perSystem.nixpkgs-unstable.bottom
      perSystem.nixpkgs-unstable.jjui
      perSystem.nixpkgs-unstable.jujutsu
      perSystem.nixpkgs-unstable.lazygit
      perSystem.nixpkgs-unstable.lnav
      perSystem.nixpkgs-unstable.mise
      perSystem.nixpkgs-unstable.neovim
      perSystem.nixpkgs-unstable.nh
      perSystem.nixpkgs-unstable.nix-visualize
      perSystem.nixpkgs-unstable.nixos-generators
      perSystem.nixpkgs-unstable.uv

      pkgs.atuin
      pkgs.awscli2
      pkgs.bacon
      pkgs.bartib
      pkgs.bat
      pkgs.broot
      pkgs.certbot
      pkgs.colima
      pkgs.curl
      pkgs.delta
      pkgs.difftastic
      pkgs.direnv
      pkgs.dive
      pkgs.dogdns
      pkgs.du-dust
      pkgs.entr
      pkgs.eza
      pkgs.fd
      pkgs.fd
      pkgs.ffmpeg
      pkgs.fish
      pkgs.freeze # code screenshot
      pkgs.fx # tui json viewer
      pkgs.fzf
      pkgs.gh
      pkgs.git-absorb
      pkgs.glab # gitlab cli
      pkgs.graphviz
      pkgs.gron
      pkgs.htmlq
      pkgs.htop
      pkgs.hyperfine
      pkgs.imagemagick
      pkgs.jless
      pkgs.jq
      pkgs.lazydocker
      pkgs.lima
      pkgs.lnav
      pkgs.lsof
      pkgs.mariadb
      pkgs.nix-output-monitor
      pkgs.nushell
      pkgs.parallel
      pkgs.procs
      pkgs.pstree
      pkgs.pv
      pkgs.python3
      pkgs.readline
      pkgs.ripgrep
      pkgs.rlwrap
      pkgs.rustup
      pkgs.shellcheck
      pkgs.shfmt
      pkgs.skim
      pkgs.soupault
      # pkgs.sqlite # needed?
      pkgs.sqlite-interactive
      pkgs.tmux
      pkgs.tokei
      pkgs.tree
      pkgs.trippy
      pkgs.unzip
      pkgs.visidata
      pkgs.watch
      pkgs.wget
      pkgs.xh
      pkgs.xz
      pkgs.yazi # directory viewer
      pkgs.yq-go
      pkgs.yt-dlp
      pkgs.zellij # multiplexer
      pkgs.zoxide
      pkgs.zstd

      # TODO: move into separate flakes
      pkgs.packwiz # for meloncraft-modpack
    ]
    ++ (
      # you can access the host configuration using osConfig.
      pkgs.lib.optionals (osConfig.programs.vim.enable && pkgs.stdenv.isDarwin) [pkgs.skhd]
    );

  # The state version is required and should stay at the version you originally installed.
  home.stateVersion = "23.05";
}
