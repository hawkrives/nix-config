{...}: {
  programs.jjui = {
    enable = true;
    # jjui itself is installed via home-shared's package list (shared across
    # hosts), so this module only manages configuration.
    package = null;

    settings = {
      ui = {
        theme = "base16-everforest-dark-hard";
        tracer.enabled = true;
      };
      keys = {
        details.close = ["h" "l"];
        inline_describe = {
          mode = ["enter"];
          accept = ["alt+enter" "ctrl+s"];
        };
      };
    };
  };

  # programs.jjui has no option for theme files, so link them directly.
  # base16-everforest-dark-hard matches Ghostty's Everforest Dark Hard
  # background (#1e2326); see the theme file header for the one deviation
  # from upstream tinted-jjui.
  xdg.configFile = {
    "jjui/themes/base16-everforest-dark-hard.toml".source =
      ./jjui/themes/base16-everforest-dark-hard.toml;
    "jjui/themes/base24-zenburn.toml".source =
      ./jjui/themes/base24-zenburn.toml;
  };
}
