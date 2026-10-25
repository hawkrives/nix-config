# Checks for the potato-bunny system layer, exposed through the package's
# passthru.tests (Blueprint names them checks.<system>.pkgs-potato-bunny-system-<name>).
#
# The activate tests run the real script against a scratch root with stub
# systemctl/synouser/synogroup that log their arguments, so nothing here needs
# DSM. Every activate test also checks that passwd/group/shadow are untouched.
{
  pkgs,
  mkGeneration,
}: let
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

  # Stubs. Each appends "<tool> <args>" to $ROOT/calls. Unit activity lives in
  # $ROOT/active/<unit>; nix-daemon's health comes from $ROOT/daemon-health.
  # Groups live in $ROOT/groups/<name> (one member per line); known users in
  # $ROOT/known-users.
  systemctlStub = pkgs.writeShellScript "systemctl" ''
    echo "systemctl $*" >> "$ROOT/calls"
    case "$1" in
      is-active)
        [ "$2" = --quiet ] && shift
        if [ "$2" = nix-daemon.service ]; then
          [ "$(cat "$ROOT/daemon-health" 2>/dev/null || echo active)" = active ]
        else
          [ -e "$ROOT/active/$2" ]
        fi ;;
      start|restart) mkdir -p "$ROOT/active"; touch "$ROOT/active/$2" ;;
      stop) rm -f "$ROOT/active/$2" ;;
      daemon-reload) ;;
      *) echo "systemctl stub: unexpected $*" >&2; exit 2 ;;
    esac
  '';
  synouserStub = pkgs.writeShellScript "synouser" ''
    echo "synouser $*" >> "$ROOT/calls"
    case "$1" in
      --get) grep -qx "$2" "$ROOT/known-users" 2>/dev/null ;;
      --add) echo "$2" >> "$ROOT/known-users" ;;
      *) echo "synouser stub: unexpected $*" >&2; exit 2 ;;
    esac
  '';
  synogroupStub = pkgs.writeShellScript "synogroup" ''
    echo "synogroup $*" >> "$ROOT/calls"
    f="$ROOT/groups/$2"
    case "$1" in
      --get)
        [ -e "$f" ] || exit 1
        echo "Group Name: [$2]"
        echo "Group Members: "
        i=0; while read -r m; do echo "$i:[$m]"; i=$((i+1)); done < "$f" ;;
      --add) mkdir -p "$ROOT/groups"; : > "$f" ;;
      --member) g=$2; shift 2; printf '%s\n' "$@" | sed '/^$/d' > "$ROOT/groups/$g" ;;
      --memberadd) echo "$3" >> "$f" ;;
      *) echo "synogroup stub: unexpected $*" >&2; exit 2 ;;
    esac
  '';

  # A scenario: fresh scratch root with DSM-owned fixtures, then `script`,
  # which calls `run <generation>` one or more times.
  scenario = name: script:
    check name ''
      export ROOT=$PWD/root
      mkdir -p $ROOT/etc/systemd/system $ROOT/volume1/@appdata
      printf 'root:x:0:0::/root:/bin/ash\nhawken:x:1027:100::/var/services/homes/hawken:/bin/sh\n' > $ROOT/etc/passwd
      printf '#$_@GID__INDEX@_$65541$\nusers:x:100:\n' > $ROOT/etc/group
      printf 'root:*:1:0:99999:7:::\n' > $ROOT/etc/shadow
      printf '[Unit]\nDescription=DSM-owned\n' > $ROOT/etc/systemd/system/synorelayd.service
      cp -a $ROOT/etc/passwd $ROOT/etc/group $ROOT/etc/shadow $ROOT/etc/systemd/system/synorelayd.service .
      echo hawken > $ROOT/known-users
      mkdir -p $ROOT/groups && : > $ROOT/groups/video   # a DSM group that already exists

      export SYSTEMCTL=${systemctlStub} SYNOUSER=${synouserStub} SYNOGROUP=${synogroupStub}
      export NIX_ENV=true ACTIVATE_DAEMON_TIMEOUT=1
      run() { : > $ROOT/calls; "$1/bin/activate" --root "$ROOT"; }
      called() { grep -qx -- "$1" $ROOT/calls; }
      called_matching() { grep -q -- "$1" $ROOT/calls; }
      link() { readlink "$ROOT/etc/systemd/system/$1"; }

      ${script}

      for f in passwd group shadow; do
        cmp -s $f $ROOT/etc/$f || fail "/etc/$f was modified"
      done
      cmp -s synorelayd.service $ROOT/etc/systemd/system/synorelayd.service || fail "DSM unit modified"
      [ ! -L $ROOT/etc/systemd/system/synorelayd.service ] || fail "DSM unit replaced by a symlink"
    '';

  unit = text: {inherit text;};
  genA = mkGeneration [
    {
      environment.etc."nix/nix.conf".text = "x = 1\n";
      systemd.units."a.service" = unit "[Service]\nExecStart=/bin/a\n";
    }
  ];
  genAB = mkGeneration [
    {
      environment.etc."nix/nix.conf".text = "x = 1\n";
      environment.etc."nix/old.conf".text = "old\n";
      systemd.units."a.service" = unit "[Service]\nExecStart=/bin/a\n";
      systemd.units."b.service" = unit "[Service]\nExecStart=/bin/b\n";
    }
  ];
  genA2 = mkGeneration [{systemd.units."a.service" = unit "[Service]\nExecStart=/bin/a2\n";}];
  genA2Exempt = mkGeneration [
    {
      systemd.units."a.service" = {
        text = "[Service]\nExecStart=/bin/a2\n";
        restartIfChanged = false;
      };
    }
  ];
  genDropIn = mkGeneration [
    {
      systemd.units."user@1027.service.d/nix-system.conf" = unit "[Service]\nEnvironment=XDG_RUNTIME_DIR=/run/user/1027\n";
      systemd.extraWants."multi-user.target" = ["user@1027.service"];
    }
  ];
  genDaemon1 = mkGeneration [{systemd.units."nix-daemon.service" = unit "[Service]\nExecStart=/old/nix-daemon\n";}];
  genDaemon2 = mkGeneration [{systemd.units."nix-daemon.service" = unit "[Service]\nExecStart=/new/nix-daemon\n";}];
  genUsers = mkGeneration [
    {
      users.users.svc-test.description = "test service";
      users.users.svc-known.extraGroups = ["video"];
      users.groups.nixbld.members = ["nixbld1" "nixbld2"];
    }
  ];
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

  etc-written = scenario "etc-written" ''
    run ${genA}
    grep -qx 'x = 1' $ROOT/etc/nix/nix.conf || fail "nix.conf content"
    [ ! -L $ROOT/etc/nix/nix.conf ] || fail "nix.conf must be a real file (it lands on the volume)"
    [ "$(stat -c %a $ROOT/etc/nix/nix.conf)" = 644 ] || fail "nix.conf mode"
  '';

  etc-removed = scenario "etc-removed" ''
    run ${genAB}
    [ -f $ROOT/etc/nix/old.conf ] || fail "old.conf not written by first run"
    echo "hand-made" > $ROOT/etc/nix/registry.json
    run ${genA}
    [ ! -e $ROOT/etc/nix/old.conf ] || fail "old.conf not removed"
    [ -f $ROOT/etc/nix/registry.json ] || fail "undeclared file removed"
  '';

  units-linked = scenario "units-linked" ''
    run ${genA}
    [ "$(link a.service)" = "${genA}/units/a.service" ] || fail "a.service link: $(link a.service)"
    [ -L $ROOT/etc/systemd/system/multi-user.target.wants/a.service ] || fail "a.service not in multi-user.target.wants"
    called "systemctl daemon-reload" || fail "no daemon-reload"
    called "systemctl start a.service" || fail "a.service not started"
  '';

  drop-in-linked = scenario "drop-in-linked" ''
    run ${genDropIn}
    [ "$(link user@1027.service.d/nix-system.conf)" = "${genDropIn}/units/user@1027.service.d/nix-system.conf" ] \
      || fail "drop-in link"
    [ "$(readlink $ROOT/etc/systemd/system/multi-user.target.wants/user@1027.service)" = /usr/lib/systemd/system/user@.service ] \
      || fail "extraWants link should point at DSM's template"
    called "systemctl start user@1027.service" || fail "user@1027 not started"
    run ${genA}
    [ ! -e "$ROOT/etc/systemd/system/user@1027.service.d" ] || fail "dropped drop-in dir left behind"
    [ ! -L $ROOT/etc/systemd/system/multi-user.target.wants/user@1027.service ] || fail "dropped extraWants link left behind"
  '';

  idempotent = scenario "idempotent" ''
    run ${genUsers}
    run ${genUsers}
    ! called_matching '^synouser --add' || fail "second run added users"
    ! called_matching '^synogroup --\(add\|member\|memberadd\) ' || fail "second run changed groups"
    run ${genA}
    run ${genA}
    ! called_matching '^systemctl \(start\|restart\|stop\) ' || fail "second run changed units: $(cat $ROOT/calls)"
  '';

  relinks-missing = scenario "relinks-missing" ''
    run ${genA}
    rm $ROOT/etc/systemd/system/a.service $ROOT/etc/systemd/system/multi-user.target.wants/a.service
    rm -f $ROOT/active/a.service   # as after a reboot that couldn't find the unit
    run ${genA}
    [ "$(link a.service)" = "${genA}/units/a.service" ] || fail "a.service not relinked"
    [ -L $ROOT/etc/systemd/system/multi-user.target.wants/a.service ] || fail "wants link not recreated"
    called "systemctl start a.service" || fail "a.service not started after relink"
    ! called "systemctl restart a.service" || fail "unchanged unit restarted"
  '';

  removes-dropped = scenario "removes-dropped" ''
    run ${genAB}
    run ${genA}
    called "systemctl stop b.service" || fail "b.service not stopped"
    [ ! -e $ROOT/etc/systemd/system/b.service ] || fail "b.service link left behind"
    [ ! -e $ROOT/etc/systemd/system/multi-user.target.wants/b.service ] || fail "b.service wants link left behind"
  '';

  ignores-foreign = scenario "ignores-foreign" ''
    ln -s /usr/lib/systemd/system/foo.service $ROOT/etc/systemd/system/foo.service
    run ${genA}
    [ "$(link foo.service)" = /usr/lib/systemd/system/foo.service ] || fail "foreign symlink touched"
    ! called_matching 'foo.service' || fail "foreign unit acted on"
  '';

  restart-changed = scenario "restart-changed" ''
    run ${genA}
    run ${genA2}
    called "systemctl restart a.service" || fail "changed a.service not restarted"
    [ "$(link a.service)" = "${genA2}/units/a.service" ] || fail "a.service not relinked to new generation"
  '';

  restart-exempt = scenario "restart-exempt" ''
    run ${genA}
    run ${genA2Exempt}
    ! called "systemctl restart a.service" || fail "restartIfChanged=false unit restarted"
  '';

  daemon-rollback = scenario "daemon-rollback" ''
    run ${genDaemon1}
    echo failed > $ROOT/daemon-health
    if run ${genDaemon2}; then fail "activate succeeded with a dead daemon"; fi
    [ "$(link nix-daemon.service)" = "${genDaemon1}/units/nix-daemon.service" ] \
      || fail "daemon not rolled back: $(link nix-daemon.service)"
    [ "$(jq -r .generation $ROOT/volume1/@appdata/nix-system/state.json)" = "${genDaemon1}" ] \
      || fail "state advanced despite failure"
  '';

  users-created = scenario "users-created" ''
    echo svc-known >> $ROOT/known-users
    run ${genUsers}
    called_matching '^synouser --add svc-test ' || fail "svc-test not created"
    ! called_matching '^synouser --add svc-known' || fail "existing user re-added"
    called "synogroup --add nixbld" || fail "missing group not created"
    called "synogroup --member nixbld nixbld1 nixbld2" || fail "membership not set"
    called "synogroup --memberadd video svc-known" || fail "extraGroups not applied"
    ! called_matching '--del' || fail "something was deleted"
  '';

  no-direct-account-writes = scenario "no-direct-account-writes" ''
    run ${genUsers}
    run ${genAB}
    run ${genDropIn}
  '';
}
