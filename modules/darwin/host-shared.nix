{
  # self, # TODO might need to remove this
  ...
}: {
  # enable dragging windows from anywhere anywhere while holding the control and command keys
  system.defaults.NSGlobalDomain.NSWindowShouldDragOnGesture = true;

  # Enable sudo authentication with Touch ID
  security.pam.services.sudo_local.touchIdAuth = true;

  # Set Git commit hash for darwin-version.
  # system.configurationRevision = self.rev or self.dirtyRev or null;

  # on mac, please give me an updated version of bash
  # because I do still need bash for things
  programs.bash.enable = true;
}
