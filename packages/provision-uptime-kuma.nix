# One-time bootstrap of Uptime Kuma's admin account, by driving its first-run
# wizard with a headless browser.
#
#   sudo nix run .#provision-uptime-kuma
#
# This is deliberately ALL this does. An earlier version also created the push
# monitors through the same web UI; that job now belongs to
# uptime-kuma-monitor-sync, which writes them into Kuma's SQLite DB directly
# (see modules/nixos/unit-heartbeat.nix for the reasoning). Driving a Vue SPA
# binds you to CSS selectors upstream changes without notice — `#monitor-type`
# had already become `#type`, and the Push URL field turned out to be rendered
# disabled, so the token could not be set from the UI at all.
#
# The admin account is the one thing that genuinely cannot move to SQL: Kuma
# stores a bcrypt hash, and writing a subtly wrong one locks you out of the UI
# with nothing in the DB to indicate why. The wizard owns that format.
#
# Not part of any system closure — this is a `nix run` package, so the Chromium
# it pulls in only lands on disk if someone actually runs it.
{ pkgs, ... }:
let
  inherit (pkgs) writeShellApplication python3 playwright-driver;

  py = python3.withPackages (ps: [ ps.playwright ]);

  script = ./provision-uptime-kuma.py;
in
writeShellApplication {
  name = "provision-uptime-kuma";
  runtimeInputs = [ py ];
  text = ''
    # Chromium comes from the nixpkgs-pinned browser bundle, not from
    # `playwright install` (which would try to download at runtime).
    export PLAYWRIGHT_BROWSERS_PATH=${playwright-driver.browsers}
    export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=1
    exec ${py}/bin/python3 ${script} "$@"
  '';
  meta.mainProgram = "provision-uptime-kuma";
}
