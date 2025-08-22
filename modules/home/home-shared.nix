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

      pkgs.nix-output-monitor
      pkgs.du-dust
      perSystem.nixpkgs-unstable.neovim
      pkgs.lsof
      perSystem.nixpkgs-unstable.lnav
      pkgs.freeze # code screenshot
      pkgs.htmlq
      pkgs.graphviz
      pkgs.shellcheck
      pkgs.gron
      pkgs.rlwrap
      pkgs.dogdns
      pkgs.tree
      pkgs.broot
      pkgs.yq-go
      pkgs.gh
      perSystem.nixpkgs-unstable.nh
      pkgs.dive
      perSystem.nixpkgs-unstable.lazygit
      pkgs.lazydocker
      pkgs.rustup
      pkgs.nushell
      pkgs.glab
      pkgs.zoxide
      pkgs.hyperfine
      pkgs.tmux
      pkgs.ripgrep
      pkgs.unzip
      pkgs.fd
      pkgs.htop
      pkgs.jq
      pkgs.xh
      pkgs.watch
      pkgs.pv
      pkgs.bat
      pkgs.tokei
      pkgs.soupault
      perSystem.nixpkgs-unstable.bottom
      pkgs.wget
      pkgs.certbot

      pkgs.ripgrep
      pkgs.sqlite
      pkgs.sqlite-interactive
      pkgs.atuin
      pkgs.awscli2
      pkgs.bacon
      pkgs.bartib
      pkgs.bat
      pkgs.broot
      pkgs.colima
      pkgs.curl
      pkgs.delta
      pkgs.difftastic
      pkgs.direnv
      pkgs.dive
      # pkgs.dog
      pkgs.entr
      pkgs.eza
      pkgs.fd
      pkgs.ffmpeg
      pkgs.fish
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
      pkgs.mariadb
      perSystem.nixpkgs-unstable.mise
      perSystem.nixpkgs-unstable.nixos-generators
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
      pkgs.sqlite
      pkgs.tmux
      pkgs.tokei
      pkgs.tree
      pkgs.trippy
      perSystem.nixpkgs-unstable.jujutsu
      perSystem.nixpkgs-unstable.jjui
      perSystem.nixpkgs-unstable.neovim
      perSystem.nixpkgs-unstable.nix-visualize
      perSystem.nixpkgs-unstable.uv
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
