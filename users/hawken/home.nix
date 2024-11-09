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
    zellij # multiplexer
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

      # Difftastic aliases, so `git dlog` is `git log` with difftastic and so on.
      dlog = "-c diff.external=difft log --ext-diff";
      dshow = "-c diff.external=difft show --ext-diff";
      ddiff = "-c diff.external=difft diff";

      # `git log` with patches shown with difftastic.
      dl = "-c diff.external=difft log -p --ext-diff";

      # Show the most recent commit with difftastic.
      ds = "-c diff.external=difft show --ext-diff";

      # `git diff` with difftastic.
      dft = "-c diff.external=difft diff";

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
      detlog = "!f() { GIT_EXTERNAL_DIFF=difft git log -p --ext-diff $@; }; f";
    };

    ignores = [
      ".DS_Store"
      "*~"
      "/.idea/"
      "/.vscode/"
      ".mise.toml"
    ];

    attributes = [
      "*.sqlite diff=sqlite3"
      "*.java merge=mergiraf"
      "*.rs merge=mergiraf"
      "*.go merge=mergiraf"
      "*.js merge=mergiraf"
      "*.jsx merge=mergiraf"
      "*.json merge=mergiraf"
      "*.yml merge=mergiraf"
      "*.yaml merge=mergiraf"
      "*.html merge=mergiraf"
      "*.htm merge=mergiraf"
      "*.xhtml merge=mergiraf"
      "*.xml merge=mergiraf"
      "*.c merge=mergiraf"
      "*.h merge=mergiraf"
      "*.cpp merge=mergiraf"
      "*.hpp merge=mergiraf"
      "*.cs merge=mergiraf"
    ];

    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      push.default = "current";
      rerere.enabled = true;
      safe.bareRepository = "explicit";

      core = {
        # Treat spaces before tabs and all kinds of trailing whitespace as an error.
        # [default] trailing-space: looks for spaces at the end of a line
        # [default] space-before-tab: looks for spaces before tabs at the beginning of a line
        whitespace = "space-before-tab,-indent-with-non-tab,trailing-space";
    
        # Make `git rebase` safer on macOS.
        # More info: <http://www.git-tower.com/blog/make-git-rebase-safe-on-osx/>
        trustctime = false;
    
        # Prevent showing files whose names contain non-ASCII symbols as unversioned.
        # http://michael-kuehnel.de/git/2014/11/21/git-mac-osx-and-german-umlaute.html
        precomposeunicode = false;
    
        # Speed up commands involving untracked files such as `git status`.
        # https://git-scm.com/docs/git-update-index#_untracked_cache
        untrackedCache = true;
      };

      "merge \"mergiraf\"" = {
        name = "mergiraf";
        driver = "mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P";
      };
    };
  };

  home.sessionPath =
    [ "$HOME/go/bin" "$HOME/bin" "$HOME/.local/bin" ];
}
