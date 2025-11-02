{inputs, ...}: {
  # enable dragging windows from anywhere anywhere while holding the control and command keys
  system.defaults.NSGlobalDomain.NSWindowShouldDragOnGesture = true;

  # Enable sudo authentication with Touch ID
  security.pam.services.sudo_local.touchIdAuth = true;

  # Set Git commit hash for darwin-version.
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
}
