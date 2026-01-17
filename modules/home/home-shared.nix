{
  pkgs,
  osConfig,
  perSystem,
  ...
}: {
  programs.fish = {
    enable = true;

    # enable the nice fish prompt
    plugins = [
      {
        name = "pure";
        src = pkgs.fishPlugins.pure.src;
      }
      {
        name = "zoxide";
        src = pkgs.fetchFromGitHub {
          owner = "icezyclon";
          repo = "zoxide.fish";
          rev = "27a058a661e2eba021b90e9248517b6c47a22674";
          hash = "sha256-OjrX0d8VjDMxiI5JlJPyu/scTs/fS/f5ehVyhAA/KDM=";
        };
      }
    ];

    shellInit = ''
      # integrate mise shims with fish
      if status is-interactive
        mise activate fish | source
      else
        mise activate fish --shims | source
      end

      # integrate brew with fish
      test (uname -s) = Darwin && test (uname -m) = arm64 && eval (/opt/homebrew/bin/brew shellenv)

      if status is-interactive
        set -gx ATUIN_NOBIND "true"
        atuin init fish | source

        # bind to ctrl-r in normal and insert mode, add any other bindings you want here too
        bind \cr _atuin_search
        bind -M insert \cr _atuin_search
      end
    '';

    functions = {
      # try overriding the pure prompt to look at jj instead
      _pure_prompt_git = "fish_jj_prompt";

      fish_vcs_prompt = {
        description = "Print all vcs prompts";
        body = ''
          # If a prompt succeeded, we assume that it's printed the correct info.
          # This is so we don't try `hg` if `git` already worked.
          fish_jj_prompt $argv
            or fish_git_prompt $argv
            or fish_hg_prompt $argv
            or fish_fossil_prompt $argv
        '';
      };

      fish_jj_prompt = {
        description = "Write out the jj prompt";
        body = ''
          # Is jj installed?
          if not command -sq jj
            return 1
          end

          # Are we in a jj repo?
          if not jj root --quiet &>/dev/null
            return 1
          end

          # Generate prompt
          jj log --ignore-working-copy --no-graph --color always -r @ -T '
            surround(
              " (",
              ")",
              separate(
                " ",
                bookmarks.join(", "),
                coalesce(
                  surround(
                    "\"",
                    "\"",
                    if(
                      description.first_line().substr(0, 24).starts_with(description.first_line()),
                      description.first_line().substr(0, 24),
                      description.first_line().substr(0, 23) ++ "…"
                    )
                  ),
                  label(if(empty, "empty"), description_placeholder)
                ),
                change_id.shortest(),
                commit_id.shortest(),
                if(conflict, label("conflict", "(conflict)")),
                if(empty, label("empty", "(empty)")),
                if(divergent, "(divergent)"),
                if(hidden, "(hidden)"),
              )
            )
          '
        '';
      };

      vidpeek = ''ffmpeg -i $argv[2] -vf "select=eq(n\,$argv[1])" -vframes 1 $argv[3]'';
      vc = ''ffmpeg -i "$argv[1]" -n -c:v libx264 -tag:v avc1 -movflags faststart -crf 30 -preset superfast "$argv[2]"'';
      vc-fast = ''
        set out (basename "$argv[1]" | string split --right --max 1 --no-empty . | head -n1).fast.mkv
        ffmpeg -i "$argv[1]" -n -c:v libx264 -tag:v avc1 -movflags faststart -crf 30 -preset fast $out
      '';
      vc-h265 = ''
        ffmpeg \
          -i "$argv[1]" \
          -n \
          -c:v libx265 \
          -x265-params no-open-gop=1:keyint=300:gop-lookahead=12:bframes=6:weightb=1:hme=1:strong-intra-smoothing=0:rect=0:aq-mode=4 \
          -tag:v hvc1 \
          -preset superfast \
          -c:a eac3 \
          -b:a 192k \
          "$argv[2]"
      '';
      vc-h265-fps30 = ''
        ffmpeg \
          -i "$argv[1]" \
          -n \
          -c:v libx265 \
          -x265-params no-open-gop=1:keyint=300:gop-lookahead=12:bframes=6:weightb=1:hme=1:strong-intra-smoothing=0:rect=0:aq-mode=4 \
          -tag:v hvc1 \
          -preset superfast \
          -c:a eac3 \
          -b:a 192k \
          "$argv[2]"
      '';
    };
  };

  # enable font lookup thing on Linux
  fonts.fontconfig.enable = pkgs.stdenv.isLinux;

  # disable home-manager man pages?
  manual.manpages.enable = false;
  programs.man.generateCaches = false;

  # provides command-not-found suggestions for missing packages:
  programs.nix-index.enable = true;

  # only available on linux, disabled on macos
  services.ssh-agent.enable = pkgs.stdenv.isLinux;

  home.sessionVariables = {
    # Indicate if a nix develop shell is activated (based on IN_NIX_SHELL).
    pure_enable_nixdevshell = "true";
    # Prefix when being connected to SSH session (default: undefined)
    pure_symbol_ssh_prefix = "§ ";
    # Show prompt prefix when logged in as root.
    pure_show_prefix_root_prompt = "true";
    # Do not check pure runs inside a container
    pure_enable_container_detection = "false";
    # Shorten all but the CWD to a single character, so ~/Developer/github.com/hawkrives/gobbldygook becomes ~/D/g/h/gobbldygook
    pure_shorten_prompt_current_directory_length = 1;
  };

  home.shellAliases = {
    ls = "ls --color=auto";
    ll = "ls -l";
    vimdiff = "nvim -d";
  };

  # TODO: relocate this
  home.sessionPath = [
    "$HOME/bin"
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    "$HOME/go/bin"
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
    lazydocker.enable = true;
    lazygit.enable = true;
    less.enable = true;
    jq.enable = true;
    nushell.enable = true;
    rclone.enable = true;
    readline.enable = true;
    ripgrep.enable = true;
    skim.enable = true;
    tmux.enable = true;
    uv.enable = true;
    zellij.enable = true; # multiplexer
    zoxide.enable = true;

    yt-dlp = {
      enable = true;
      package = pkgs.yt-dlp-light; # to get ffmpeg-headless
    };

    yazi = {
      enable = true; # directory viewer
      package = pkgs.yazi-unwrapped; # disable a bunch of plugins
    };

    mise = {
      enable = true;
      globalConfig = {
        tools."pipx:batrachian-toad" = "0.5.34";
        settings.experimental = true;
      };
    };
  };

  programs.neovim = {
    enable = true;
    package = pkgs.neovim-unwrapped;
    withRuby = false; # don't need any ruby neovim plugins
    withNodeJs = false;
    withPython3 = false;
    vimAlias = true;
    viAlias = true;
  };

  # programs.visidata = {
  #   enable = true; # installs X and Wayland on Linux thanks to Xclip...
  #   package = pkgs.visidata.override {
  #     withXclip = false;
  #     withPcap = false;
  #     matplotlib = matplotlibNoX;
  #   };
  # };

  # TODO: use programs.ssh to control the ssh config file

  home.packages =
    [
      # pkgs.nixos-generators

      pkgs.alejandra # nix formatter
      pkgs.bartib
      pkgs.buildah
      pkgs.certbot
      pkgs.curl
      pkgs.diffoci
      pkgs.dive
      pkgs.doggo # maintained fork of dogdns
      pkgs.dust
      pkgs.entr
      pkgs.ffmpeg-headless
      pkgs.freeze # code screenshot
      pkgs.fx # tui json viewer
      pkgs.glab # gitlab cli
      pkgs.graphviz
      pkgs.gron
      pkgs.htmlq
      pkgs.hyperfine
      pkgs.imagemagick
      pkgs.jjui
      # pkgs.jj-fzf
      pkgs.jless
      pkgs.lazyjj
      pkgs.lnav
      pkgs.lsof
      pkgs.mariadb.client
      pkgs.nix-output-monitor
      pkgs.parallel
      pkgs.procs
      pkgs.pstree
      pkgs.pv
      pkgs.readline
      pkgs.rlwrap
      pkgs.rustup
      pkgs.shellcheck
      pkgs.shfmt
      pkgs.soupault
      pkgs.sqlite-interactive
      pkgs.terraform
      pkgs.tokei
      pkgs.tree
      pkgs.trippy
      pkgs.unzip
      pkgs.watch
      pkgs.watchexec
      pkgs.wget
      pkgs.xh
      pkgs.xz
      pkgs.yq-go
      pkgs.zstd

      pkgs.gemini-cli
      pkgs.copilot-cli
      pkgs.codex
      pkgs.claude-code

      pkgs.nodejs-slim
      pkgs.pnpm

      # TODO: move into separate flakes
      # pkgs.packwiz # for meloncraft-modpack
    ]
    # you can access the host configuration using osConfig.
    ++ (pkgs.lib.optionals (osConfig.programs.vim.enable && pkgs.stdenv.isDarwin) [pkgs.skhd])
    ++ (pkgs.lib.optionals (pkgs.stdenv.isLinux) []);

  targets =
    if pkgs.stdenv.isDarwin
    then {
      darwin.defaults = {
        "com.apple.dock".autohide = true;
        "com.apple.dock".mru-spaces = false;
        "com.apple.dock".mouse-over-hilite-stack = true;
        "com.apple.dock".showhidden = true;
        "com.apple.dock".slow-motion-allowed = false;

        "screencapture".disable-shadow = true;

        "com.apple.finder".ShowPathbar = true;
        "com.apple.finder".ShowStatusBar = true;

        "com.apple.menuextra.clock".Show24Hour = true;
        "com.apple.menuextra.clock".ShowAMPM = false;

        "universalaccess".closeViewScrollWheelToggle = true; # Use scroll gesture with the Ctrl (^) modifier key to zoom.
        # "universalaccess".reduceMotion = true;
      };
    }
    else {};

  # The state version is required and should stay at the version you originally installed.
  home.stateVersion = "23.05";
}
