# Checks for the potato-bunny system layer, exposed through the package's
# passthru.tests (Blueprint names them checks.<system>.pkgs-potato-bunny-system-<name>).
{
  pkgs,
  mkGeneration,
}: let
  inherit (pkgs) lib;

  check = name: script:
    pkgs.runCommand "potato-bunny-system-${name}" {nativeBuildInputs = [pkgs.jq];} ''
      set -euo pipefail
      fail() { echo "FAIL: $*" >&2; exit 1; }
      ${script}
      touch $out
    '';

  layoutGen = mkGeneration [
    {
      environment.etc."nix/nix.conf".text = "x = 1\n";
      systemd.units."a.service".text = "[Service]\nExecStart=/bin/true\n";
      systemd.units."user@1027.service.d/nix-system.conf".text = "[Service]\nEnvironment=A=1\n";
      users.groups.nixbld.members = ["nixbld1"];
    }
  ];
  rejects = modules: !(builtins.tryEval (mkGeneration modules).drvPath).success;
in {
  assertions-reject = assert rejects [{environment.etc."passwd".text = "";}];
  assert rejects [{users.users.plex = {};}];
  assert !(rejects [{users.users.svc-plex = {};}]);
    check "assertions-reject" "";

  generation-layout = check "generation-layout" ''
    g=${layoutGen}
    grep -qx 'x = 1' $g/etc/nix/nix.conf || fail "nix.conf content"
    [ -f $g/units/a.service ] || fail "units/a.service missing"
    [ -e $g/wants/multi-user.target/a.service ] || fail "a.service not wanted by multi-user.target"
    [ -f "$g/units/user@1027.service.d/nix-system.conf" ] || fail "drop-in missing"
    [ ! -e "$g/wants/multi-user.target/user@1027.service.d" ] || fail "drop-in must not be wanted"
    jq -e '.groups.nixbld == ["nixbld1"]' $g/users.json >/dev/null || fail "users.json groups"
    jq -e '.users == {}' $g/users.json >/dev/null || fail "users.json users"
    [ -x $g/bin/activate ] || fail "bin/activate not executable"
  '';
}
