{
  pkgs,
  osConfig,
  perSystem,
  ...
}: let
  matplotlibNoX = perSystem.nixpkgs-unstable.python313Packages.matplotlib.override {
    enableTk = false;
  };
in {
  programs.fish = {
    enable = true;

    # enable the nice fish prompt
    plugins = [
      {
        name = "pure";
        src = pkgs.fishPlugins.pure.src;
      }
    ];

    shellInit = ''
      # integrate mise shims with fish
      if status is-interactive
          mise activate fish | source
      else
          mise activate fish --shims | source
      end
    '';
  };

  # disable home-manager man pages?
  manual.manpages.enable = false;
  programs.man.generateCaches = false;

  # provides command-not-found suggestions for missing packages:
  programs.nix-index.enable = true;

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
    # "$HOME/.cargo/bin"
    # "$HOME/go/bin"
    "$HOME/bin"
    "$HOME/.local/bin"
    # "/opt/homebrew/bin"
  ];

  programs = {
    atuin.enable = true;
    bacon.enable = true;
    bat.enable = true;
    broot.enable = true;
    dircolors.enable = true;
    direnv.enable = true;
    eza.enable = true;
    fd.enable = true;
    fzf.enable = true;
    gh.enable = true;
    htop.enable = true;
    jq.enable = true;
    less.enable = true;
    nushell.enable = true;
    rclone.enable = true;
    readline.enable = true;
    ripgrep.enable = true;
    skim.enable = true;
    tmux.enable = true;
    zellij.enable = true; # multiplexer
    zoxide.enable = true;
  };

  programs.lazydocker = {
    enable = true;
    package = perSystem.nixpkgs-unstable.lazydocker;
  };

  programs.lazygit = {
    enable = true;
    package = perSystem.nixpkgs-unstable.lazygit;
  };

  programs.mise = {
    enable = true;
    package = perSystem.nixpkgs-unstable.mise;
    settings = {
      experimental = true;
    };
  };

  programs.neovim = {
    enable = true;
    package = perSystem.nixpkgs-unstable.neovim-unwrapped;
    withRuby = false; # don't need any ruby neovim plugins
    withNodeJs = false;
    withPython3 = false;
    vimAlias = true;
    viAlias = true;
  };

  programs.uv = {
    enable = true;
    package = perSystem.nixpkgs-unstable.uv;
  };

  # programs.visidata = {
  #   enable = true; # installs X and Wayland on Linux thanks to Xclip...
  #   package = perSystem.nixpkgs-unstable.visidata.override {
  #     withXclip = false;
  #     withPcap = false;
  #     matplotlib = matplotlibNoX;
  #   };
  # };

  programs.yazi = {
    enable = true; # directory viewer
    package = pkgs.yazi-unwrapped; # disable a bunch of plugins
  };

  programs.yt-dlp = {
    enable = true; # directory viewer
    package = perSystem.nixpkgs-unstable.yt-dlp-light; # to get ffmpeg-headless
  };

  # TODO: use programs.ssh to control the ssh config file

  home.packages =
    [
      perSystem.alejandra.default # nix formatter

      perSystem.nixpkgs-unstable.jjui
      perSystem.nixpkgs-unstable.lnav
      (perSystem.nixpkgs-unstable.nix-visualize.override {
        nix = perSystem.lix-module.default;
        matplotlib = matplotlibNoX;
      })
      pkgs.nixos-generators

      pkgs.bartib
      pkgs.certbot
      pkgs.curl
      pkgs.dive
      pkgs.dogdns
      pkgs.du-dust
      pkgs.entr
      pkgs.ffmpeg-headless
      pkgs.freeze # code screenshot
      pkgs.fx # tui json viewer
      pkgs.glab # gitlab cli
      pkgs.graphviz
      pkgs.gron
      pkgs.htmlq
      pkgs.hyperfine
      (pkgs.imagemagick.override {})
      pkgs.jless
      pkgs.lsof
      # pkgs.mariadb
      pkgs.nix-output-monitor
      pkgs.parallel
      pkgs.procs
      pkgs.pstree
      pkgs.pv
      pkgs.python3
      pkgs.readline
      pkgs.rlwrap
      pkgs.rustup
      pkgs.shellcheck
      pkgs.shfmt
      pkgs.soupault
      pkgs.sqlite-interactive
      pkgs.tokei
      pkgs.tree
      pkgs.trippy
      pkgs.unzip
      pkgs.watch
      pkgs.wget
      pkgs.xh
      pkgs.xz
      pkgs.yq-go
      pkgs.zstd

      # TODO: move into separate flakes
      pkgs.packwiz # for meloncraft-modpack
    ]
    ++ (
      # you can access the host configuration using osConfig.
      pkgs.lib.optionals (osConfig.programs.vim.enable && pkgs.stdenv.isDarwin) [
        pkgs.skhd
      ]
    );

  # The state version is required and should stay at the version you originally installed.
  home.stateVersion = "23.05";
}
