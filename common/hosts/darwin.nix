{ config, pkgs, ... }: {
  environment.systemPackages = with pkgs; [ vim ];
  environment.shells = with pkgs; [ bashInteractive fish ];

  nix.settings.experimental-features = "nix-command flakes";

  programs.zsh.enable = true;  # default shell on catalina
  programs.fish.enable = true;

  # enable dragging windows from anywhere anywhere while holding the control and command keys
  system.defaults.NSGlobalDomain.NSWindowShouldDragOnGesture = true;

  # Enable sudo authentication with Touch ID
  security.pam.services.sudo_local.touchIdAuth = true;

  # Set Git commit hash for darwin-version.
  #system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
