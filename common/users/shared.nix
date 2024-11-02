{ pkgs, config, ... }:

{
  # The state version is required and should stay at the version you
  # originally installed.
  home.stateVersion = "23.05";

  programs.home-manager.enable = true;

  home.shellAliases = {
    ls = "ls --color=auto";
    ll = "ls -l";
    view = "nvim -R";
    vimdiff = "nvim -d";
    gs = "git status";
    gd = "git diff";
    gdc = "git diff --cached";
  };

  programs.bash = {
    enable = true;
    historyControl = [ "ignoredups" "ignorespace" ];
  };

  home.sessionVariables = {
    EDITOR = "hx";
  };

  programs.dircolors.enable = true;
  programs.direnv.enable = true;

  home.file.".sqliterc".text = ''
    .header on
    .mode column
  '';

  programs.git.extraConfig = {
    "diff \"sqlite3\"".binary = true;
    "diff \"sqlite3\"".textconv = "echo .dump | sqlite3";
    diff.colormoved = "default";
    diff.colormovedws = "allow-indentation-change";
    merge.conflictStyle = "zdiff3";
    diff.algorithm = "histogram";
    transfer.fsckobjects = true;
    fetch.fsckobjects = true;
    receive.fsckobjects = true;
    fetch.prune = true;
    fetch.prunetags = true;
    core.hooksPath = "${config.xdg.configHome}/git/hooks";
  };

  programs.readline = {
    variables = {
      colored-stats = true;
      colored-completion-prefix = true;
      keyseq-timeout = 1200;
    };
  };

  home.file."${config.xdg.configHome}/git/ignore".text = ''
  .DS_Store
  .idea
  '';

  home.file.".gitattributes".text = ''
    *.sqlite diff=sqlite3
  '';

  home.sessionPath = [ "$HOME/.cargo/bin" "$HOME/go/bin" "$HOME/bin" "$HOME/.local/bin" "/opt/homebrew/bin" ];
}
