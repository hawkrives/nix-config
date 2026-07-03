{...}: {
  # Ghostty on macOS is installed via the official Ghostty.app (the nixpkgs
  # package is unsupported on darwin), so package is null and this module only
  # manages configuration. Written to ~/.config/ghostty/config, which Ghostty
  # reads on macOS. Import this only from macOS home configs.
  programs.ghostty = {
    enable = true;
    package = null;

    settings = {
      copy-on-select = "clipboard";
      theme = "Everforest Dark Hard";
      scrollback-limit = 100000000;
      shell-integration-features = "ssh-terminfo,ssh-env";
      # Send ESC + CR on shift+enter (e.g. for multi-line prompts).
      keybind = ["shift+enter=text:\\x1b\\r"];
    };

    # Ghostty.app injects shell integration automatically on macOS, so don't
    # also add manual sourcing to the shell rc.
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableZshIntegration = false;
  };
}
