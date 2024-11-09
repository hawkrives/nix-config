{ unstable-pkgs }:

{ pkgs, config, ... }:

{
  imports = [ ../../common/users/shared.nix ];

  home.packages = with pkgs; [
    atuin
    awscli2
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
    uv
    visidata
    watch
    wget
    xh
    xsv
    xz
    yazi # directory viewer
    yq
    yt-dlp
    zellij
    zstd
  ];

  programs.git = {
    enable = true;
    aliases = {
      # View abbreviated SHA, description, and history graph of the latest 20 commits.
      l = "log --pretty=oneline -n 20 --graph --abbrev-commit";

      # View the current working tree status using the short format.
      s = "status -s";

      # Show the diff between the latest commit and the current state.
      d = "!git diff-index --quiet HEAD -- || clear; git --no-pager diff --patch-with-stat";

      # `git di $number` shows the diff between the state `$number` revisions ago and the current state.
      di = "!d() { git diff --patch-with-stat HEAD~$1; }; git diff-index --quiet HEAD -- || clear; d";

      co = "checkout";
      st = "status";
      ci = "commit";
      br = "branch";

      tags = "tag -l";
      branches = "branch --all";
      remotes = "remote --verbose";

      # Remove branches that have already been merged with main; a.k.a. ‘delete merged’
	    dm = "!git branch --merged | grep -v '\\*' | xargs -n 1 git branch -d";
      
      # "git lol" is a log alias. It shows a pretty graph of the last 25 commits.
      lol = "!git --no-pager log --graph --decorate --abbrev-commit --all --date=local -25 --pretty=short";

      # "git sw" shows branches in fzf; hit enter on one and you checkout that branch.
      sw = "!git checkout $(git branch -a --format '%(refname:short)' | sed 's~origin/~~' | sort | uniq | fzf)";

      # "git lc" just shows the last commit.
      lc = "!git rev-parse HEAD";

      # "git rb" shows recent branches, sorted by most recent commit.
      rb = "!git for-each-ref --sort=-committerdate refs/heads/ --format='%(refname:short) %(objectname:short) %(committerdate:format:%F)' | column -t | sort -k3";
      
      # "git fza" (aliased to "ga") shows all unstaged files in fzf and you can
      # use space to toggle them, then hitting enter finishes adding/staging
      # them. This is great for selecting some files to stage. I use this one
      # every day, it makes my workflow just a little better :)
      fza = "!git ls-files -m -o --exclude-standard | fzf -m --print0 | xargs -0 git add";

      # "git root" is part of an alias "gr" which runs "cd $(git root)". That
      # takes you to the project root, and "cd -" will take you back to your
      # previous location.
      root = "rev-parse --show-toplevel";

      # "git oldest-ancestor brancha branchb" does what it says. It finds the oldest ancestor of two branches.
      oldest-ancestor = "!zsh -c 'diff -u <(git rev-list --first-parent \"\${1:-main}\") <(git rev-list --first-parent \"\${2:-HEAD}\") | sed -ne 's/^ //p' | head -1' -";
      diverges = "!sh -c 'git rev-list --boundary $1...$2 | grep \"^-\" | cut -c2-'";

      # "git dlog" shows a detailed commit log.
      dlog = "!f() { GIT_EXTERNAL_DIFF=difft git log -p --ext-diff $@; }; f";
    };
    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
    };
  };

  home.sessionPath =
    [ "$HOME/go/bin" "$HOME/bin" "$HOME/.local/bin" ];
}
