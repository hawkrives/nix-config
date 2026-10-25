# hawken on potato-bunny (the Synology). Deliberately minimal: the tools that
# used to live in a hand-managed `nix profile`, the patched Lix, and the login
# hook. The fleet's *-shared modules aren't imported; fish/helix/git configs
# on the NAS stay hand-managed for now.
{
  flake,
  pkgs,
  perSystem,
  ...
}: {
  imports = [flake.homeModules.dsm-user-services];

  home.homeDirectory = "/var/services/homes/hawken";
  home.stateVersion = "23.05";

  home.packages = [
    perSystem.self.lix-dsm
    pkgs.broot
    pkgs.btop
    pkgs.curl
    pkgs.fd
    pkgs.file
    pkgs.fish
    pkgs.git
    pkgs.helix
    pkgs.htop
    pkgs.iftop
    pkgs.iotop-c
    pkgs.jq
    pkgs.less
    pkgs.lsof
    pkgs.man
    pkgs.neovim
    pkgs.pv
    pkgs.ripgrep
    pkgs.rlwrap
    pkgs.rsync
    pkgs.tmux
    pkgs.tree
    pkgs.unzip
    pkgs.watch
    pkgs.wget
    pkgs.zellij
    pkgs.zip
    pkgs.zstd
  ];

  # The login shell is DSM's /bin/sh, which reads ~/.profile. Nix comes from
  # the default profile's daemon hook; home-manager's own session variables
  # from hm-session-vars.
  home.file.".profile".text = ''
    test -e "$HOME/.shellfishrc" && . "$HOME/.shellfishrc"

    export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive

    if test -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh; then
      . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi
    if test -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"; then
      . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    fi

    # exec fish

    test -e "$HOME/.local/bin/env" && . "$HOME/.local/bin/env"
    test -e "$HOME/.cargo/env" && . "$HOME/.cargo/env"
  '';
}
