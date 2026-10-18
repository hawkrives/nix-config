{pkgs, ...}:
# alejandra reads stdin when given no path, which makes a bare `nix fmt` do
# nothing. Format the current directory unless a path is passed.
pkgs.writeShellApplication {
  name = "alejandra-fmt";
  runtimeInputs = [pkgs.alejandra];
  text = ''
    for arg in "$@"; do
      case "$arg" in
        -*) ;;
        *) exec alejandra "$@" ;;
      esac
    done
    exec alejandra "$@" .
  '';
}
