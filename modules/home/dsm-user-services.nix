# systemd user services on a Synology (DSM 7). home-manager's sd-switch needs
# a user D-Bus, which DSM doesn't run, so this turns it off and restarts
# changed units with dsm-user-units.sh instead. The user manager itself is
# started at boot by the potato-bunny system layer (homeUsers in
# hosts/potato-bunny/system.nix); when it isn't running, this skips.
{
  lib,
  pkgs,
  ...
}: let
  script = pkgs.writeShellApplication {
    name = "dsm-user-units";
    runtimeInputs = [pkgs.coreutils pkgs.diffutils];
    text = builtins.readFile ./dsm-user-units.sh;
  };
  uid = "$(id -u)";
in {
  systemd.user.startServices = false;

  home.activation.dsmRestartUserUnits = lib.hm.dag.entryAfter ["reloadSystemd"] ''
    export XDG_RUNTIME_DIR=''${XDG_RUNTIME_DIR:-/run/user/${uid}}
    if [ -S "$XDG_RUNTIME_DIR/systemd/private" ]; then
      run ${lib.getExe script} \
        "''${oldGenPath:-/nonexistent}/home-files/.config/systemd/user" \
        "$newGenPath/home-files/.config/systemd/user"
    else
      warnEcho "systemd user manager for $USER isn't running; user services not (re)started"
    fi
  '';
}
