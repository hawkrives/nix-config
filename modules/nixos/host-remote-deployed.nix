# Hosts that are only ever deployed from nutmeg (`nh os switch --target-host`)
# and administered over SSH. Nobody reads docs or rebuilds on them, so drop the
# man pages (and the man-db cache service in documentation.nix) and the on-host
# rebuild tooling.
#
# A remote deploy still needs `nix` (copy-closure, setting the system profile)
# and the toplevel's own switch-to-configuration, so those stay. nixos-version
# stays too: it's how you check what a host is running.
{lib, ...}: {
  # Covers man, info, doc and the NixOS manual.
  documentation.enable = false;
  documentation.man.enable = false;

  # nh's GC timer (programs.nh.clean) doesn't depend on this.
  programs.nh.enable = false;

  # Don't pin a nixpkgs source tree (~500 MB) into the closure for
  # `nix shell nixpkgs#…` / NIX_PATH; nothing evaluates nixpkgs on these hosts.
  nixpkgs.flake.setNixPath = false;
  nixpkgs.flake.setFlakeRegistry = false;
  nix.registry = lib.mkForce {};

  system.tools = {
    nixos-rebuild.enable = false;
    nixos-install.enable = false;
    nixos-enter.enable = false;
    nixos-option.enable = false;
  };
}
