{inputs, ...}: {
  # enable dragging windows from anywhere anywhere while holding the control and command keys
  system.defaults.NSGlobalDomain.NSWindowShouldDragOnGesture = true;

  # Enable sudo authentication with Touch ID
  security.pam.services.sudo_local.touchIdAuth = true;

  # Set Git commit hash for darwin-version.

  # on mac, please give me an updated version of bash
  # because I do still need bash for things
  programs.bash.enable = true;
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
}
