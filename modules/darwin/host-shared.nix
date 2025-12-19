{inputs, ...}: {
  # enable dragging windows from anywhere anywhere while holding the control and command keys
  system.defaults.NSGlobalDomain.NSWindowShouldDragOnGesture = true;

  # reduce spacing around menu bar items
  # system.defaults.NSGlobalDomain.NSStatusItemSelectionPadding = 6;
  # system.defaults.NSGlobalDomain.NSStatusItemSpacing = 12;

  # enable column auto-resize in Findeer
  # system.defaults.finder._FXEnableColumnAutoSizing = true;

  # Enable sudo authentication with Touch ID
  security.pam.services.sudo_local.touchIdAuth = true;

  # on darwin, please give me an updated version of bash because I do
  # still need bash for things. nixos doesn't use this option anymore.
  programs.bash.enable = true;

  # Set Git commit hash for darwin-version.
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
}
