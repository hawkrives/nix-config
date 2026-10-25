# Checks for the potato-bunny system layer, exposed through the package's
# passthru.tests (Blueprint names them checks.<system>.pkgs-potato-bunny-system-<name>).
#
# The activate tests run the real script against a scratch root with stub
# systemctl/synouser/synogroup that log their arguments, so nothing here needs
# DSM. Every activate test also checks that passwd/group/shadow are untouched.
{
  pkgs,
  mkGeneration,
  hostGeneration,
  hawkenHome,
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
  # nix-daemon's behaviour after a (re)start comes from $ROOT/daemon-health:
  #   ok (default)  active and answering
  #   crashloop     systemd says active, but the socket never answers
  #   dead          not active at all
  systemctlStub = pkgs.writeShellScript "systemctl" ''
    echo "systemctl $*" >> "$ROOT/calls"
    unit=''${*: -1}
    health=$(cat "$ROOT/daemon-health" 2>/dev/null || echo ok)
    case "$1" in
      is-active)
        [ -e "$ROOT/active/$unit" ] || exit 1
        [ "$unit" != nix-daemon.service ] || [ "$health" != dead ] ;;
      start|restart) mkdir -p "$ROOT/active"; touch "$ROOT/active/$unit" ;;
      stop) rm -f "$ROOT/active/$unit" ;;
      daemon-reload) ;;
      *) echo "systemctl stub: unexpected $*" >&2; exit 2 ;;
    esac
  '';
  # Stands in for "the daemon answers on its socket".
  probeStub = pkgs.writeShellScript "probe" ''
    [ -e "$ROOT/active/nix-daemon.service" ] && [ "$(cat "$ROOT/daemon-health" 2>/dev/null || echo ok)" = ok ]
  '';
  # nix-env -p <profile> --set <path>: just repoint the profile link.
  nixEnvStub = pkgs.writeShellScript "nix-env" ''
    echo "nix-env $*" >> "$ROOT/calls"
    [ "$1" = -p ] && [ "$3" = --set ] || { echo "nix-env stub: unexpected $*" >&2; exit 2; }
    mkdir -p "$(dirname "$2")"
    # Like the real one, --set takes the store path *containing* its argument:
    # /nix/store/<gen>/default-profile becomes /nix/store/<gen>.
    target=$(echo "$4" | sed -E "s|^(/nix/store/[^/]+).*|\\1|")
    ln -sfn "$target" "$2"
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

  # User-unit scenarios: `unit <old|new> <name> <body>` and `want <old|new> <name>`
  # build two home-files unit dirs; `go` runs the script on them.
  userUnitsScript = pkgs.writeShellApplication {
    name = "dsm-user-units";
    runtimeInputs = [pkgs.coreutils pkgs.diffutils];
    text = builtins.readFile ../../modules/home/dsm-user-units.sh;
  };
  userUnitsStub = pkgs.writeShellScript "systemctl" ''
    echo "systemctl $*" >> "$CALLS"
  '';
  userUnits = name: script:
    check "user-units-${name}" ''
      mkdir -p old new
      export CALLS=$PWD/calls SYSTEMCTL=${userUnitsStub}
      : > $CALLS
      unit() { printf "[Service]\n%s\n" "$3" > "$1/$2"; }
      want() { mkdir -p "$1/default.target.wants"; ln -s "../$2" "$1/default.target.wants/$2"; }
      go() { ${pkgs.lib.getExe userUnitsScript} "$PWD/old" "$PWD/new"; }
      called() { grep -qx -- "$1" $CALLS; }
      called_matching() { grep -q -- "$1" $CALLS; }
      ${script}
    '';

  # DSM's Task Scheduler API: tasks live in $ROOT/tasks/<name>.json as the
  # "data" object get returns; a missing task gets success with no data.
  synowebapiStub = pkgs.writeShellScript "synowebapi" ''
    [ "$1" = --exec ] && shift
    method="" name="" obj='{}'
    for arg in "$@"; do
      key=''${arg%%=*} val=''${arg#*=}
      case "$key" in
        api|version) ;;
        method) method=$val ;;
        *) obj=$(${pkgs.jq}/bin/jq -c --arg k "$key" --argjson v "$val" '. + {($k): $v}' <<<"$obj")
           [ "$key" = task_name ] && name=$(${pkgs.jq}/bin/jq -r . <<<"$val") ;;
      esac
    done
    echo "synowebapi $method $name" >> "$ROOT/calls"
    f="$ROOT/tasks/$name.json"
    case "$method" in
      get) if [ -f "$f" ]; then ${pkgs.jq}/bin/jq -c '{data: ., success: true}' "$f"; else echo '{"success":true}'; fi ;;
      create|set) mkdir -p "$ROOT/tasks"; echo "$obj" > "$f"; echo '{"success":true}' ;;
      delete) rm -f "$f"; echo '{"success":true}' ;;
      *) echo "synowebapi stub: unexpected $*" >&2; exit 2 ;;
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

      mkdir -p $ROOT/usr/lib/systemd/system
      printf '[Service]\nExecStart=/usr/lib/systemd/systemd --user\n' > "$ROOT/usr/lib/systemd/system/user@.service"

      export SYSTEMCTL=${systemctlStub} SYNOUSER=${synouserStub} SYNOGROUP=${synogroupStub} SYNOWEBAPI=${synowebapiStub}
      export DAEMON_PROBE=${probeStub} NIX_ENV=${nixEnvStub} ACTIVATE_DAEMON_TIMEOUT=1
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
  genMediaGroup = mkGeneration [
    {
      users.users.svc-a.extraGroups = ["media"];
      users.groups.media = {};
    }
  ];
  genDaemonConf = conf:
    mkGeneration [
      {
        environment.etc."nix/nix.conf".text = conf;
        systemd.units."nix-daemon.service" = unit "[Service]\nExecStart=/old/nix-daemon\n";
      }
    ];
  genCollidesDsm = mkGeneration [{systemd.units."synorelayd.service" = unit "[Service]\nExecStart=/bin/x\n";}];
  genCollidesTemplate = mkGeneration [{systemd.units."user@.service" = unit "[Service]\nExecStart=/bin/x\n";}];
  genProfile = mkGeneration [{nix.package = pkgs.hello;}];
  genUserUnit = mkGeneration [
    {
      users.users.svc-foo = {};
      systemd.units."foo.service" = unit "[Service]\nUser=svc-foo\nExecStart=/bin/foo\n";
    }
  ];
  genDaemonAndA = mkGeneration [
    {
      systemd.units."nix-daemon.service" = unit "[Service]\nExecStart=/old/nix-daemon\n";
      systemd.units."a.service" = unit "[Service]\nExecStart=/bin/a\n";
    }
  ];
  genTasks = script:
    mkGeneration [
      {
        dsm.tasks."HDD db" = {
          event = "bootup";
          inherit script;
          notifyOnError = true;
          notifyMail = "me@example.com";
        };
      }
    ];
  multilineScript = "#!/bin/sh\nprintf 'hawken ALL=(ALL) NOPASSWD: ALL\\n' > /tmp/x\nchmod 0440 /tmp/x";
  genTaskDepends = mkGeneration [
    {
      dsm.tasks."HDD db" = {
        event = "bootup";
        script = "x";
      };
      dsm.tasks.dedupe = {
        event = "bootup";
        script = "y";
        dependsOn = "HDD db";
      };
    }
  ];
  genServices = mkGeneration [
    {
      dsm.services.smb = {
        enable = true;
        settings.smb_max_protocol = 3;
      };
      dsm.services.ssh.enable = true;
      dsm.services.foo = {
        package = "Foo";
        enable = false;
      };
      dsm.packageSources.SynoCommunity = "https://packages.synocommunity.com/";
    }
  ];
  genSchedule = mkGeneration [
    {
      dsm.tasks.t = {
        event = "schedule";
        script = "x";
        schedule = {
          hour = 0;
          minute = 0;
        };
      };
    }
  ];
  installerDaemon = "/nix/var/nix/profiles/default/lib/systemd/system/nix-daemon.service";
  installerSocket = "/nix/var/nix/profiles/default/lib/systemd/system/nix-daemon.socket";
in {
  host-config = check "host-config" ''
    g=${hostGeneration}
    grep -qx 'trusted-users = root hawken' $g/etc/nix/nix.conf || fail "trusted-users"
    grep -qx 'build-users-group = nixbld' $g/etc/nix/nix.conf || fail "build-users-group"
    grep -qx 'sandbox = true' $g/etc/nix/nix.conf || fail "sandbox"
    ! grep -q filter-syscalls $g/etc/nix/nix.conf || fail "filter-syscalls is unknown to Lix"
    grep -q 'lix-2.96.0/bin/nix-daemon --daemon' $g/units/nix-daemon.service || fail "daemon ExecStart"
    [ -L $g/default-profile ] && [ -x $g/default-profile/bin/nix-env ] || fail "default profile lacks nix-env"
    [ -e $g/default-profile/etc/ssl/certs/ca-bundle.crt ] || fail "default profile lacks cacert"
    [ -f $g/units/user-runtime-dir-1027.service ] || fail "runtime dir unit"
    grep -q '/run/user/1027' $g/units/user-runtime-dir-1027.service || fail "runtime dir path"
    grep -q 'XDG_RUNTIME_DIR=/run/user/1027' "$g/units/user@1027.service.d/nix-system.conf" || fail "user@1027 drop-in"
    grep -q 'Requires=user-runtime-dir-1027.service' "$g/units/user@1027.service.d/nix-system.conf" || fail "user@1027 requires runtime dir"
    [ -e "$g/wants/multi-user.target/user@1027.service" ] || fail "user@1027 not wanted at boot"
    grep -qx user-runtime-dir-1027.service $g/restart-exempt || fail "runtime dir unit restarts (and drags user@1027 along) when its store paths change"
    jq -e '.groups.nixbld | length == 32' $g/users.json >/dev/null || fail "nixbld members"
    grep -q "$g/default-profile/bin/nix-env" $g/bin/activate || fail "activate does not default to its own nix-env"
  '';

  hm-hawken = check "hm-hawken" ''
    h=${hawkenHome}
    grep -q nix-daemon.sh $h/home-files/.profile || fail ".profile lost the nix-daemon.sh hook"
    grep -q hm-session-vars.sh $h/home-files/.profile || fail ".profile does not load hm-session-vars"
    grep -q dsm-user-units $h/activate || fail "activation does not restart user units"
    [ -x $h/home-path/bin/rg ] || fail "no rg"
    [ -x $h/home-path/bin/btop ] || fail "no btop"
    $h/home-path/bin/nix --version | grep -q 2.96.0 || fail "nix is not lix-dsm"
    grep -q "lix-2.96.0" <(readlink -f $h/home-path/bin/nix) || fail "nix not from lix"
  '';

  user-units-start-new = userUnits "start-new" ''
    unit new a.service "ExecStart=/bin/a"; want new a.service
    unit new idle.service "ExecStart=/bin/idle"
    go
    called "systemctl --user daemon-reload" || fail "no daemon-reload"
    called "systemctl --user start a.service" || fail "new wanted unit not started"
    ! called_matching "idle.service" || fail "unwanted unit started"
  '';

  user-units-restart-changed = userUnits "restart-changed" ''
    unit old a.service "ExecStart=/bin/a"; want old a.service
    unit new a.service "ExecStart=/bin/a2"; want new a.service
    unit old same.service "ExecStart=/bin/s"; unit new same.service "ExecStart=/bin/s"
    go
    called "systemctl --user try-restart a.service" || fail "changed unit not restarted"
    ! called_matching "same.service" || fail "unchanged unit touched"
  '';

  user-units-stop-removed = userUnits "stop-removed" ''
    unit old gone.service "ExecStart=/bin/g"; want old gone.service
    go
    called "systemctl --user stop gone.service" || fail "removed unit not stopped"
  '';

  user-units-first-run = userUnits "first-run" ''
    unit new a.service "ExecStart=/bin/a"; want new a.service
    rm -rf old   # first home-manager generation: no old one
    go
    called "systemctl --user start a.service" || fail "not started on first run"
  '';

  beszel-unit = check "beszel-unit" ''
    u=${hostGeneration}/units/beszel-agent.service
    [ -f $u ] || fail "no beszel-agent.service"
    for want in \
      'HUB_URL=http://[2600:2b00:9b16:6d01::228]:8091' \
      'KEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINIxBO27YxooTl6NWl1Jf8v/AAanacdGhJf9VF1t2yds' \
      'DATA_DIR=/volume1/docker/beszel-agent/data' \
      'SYS_SENSORS=/volume1/docker/beszel-agent/sensors' \
      'PRIMARY_SENSOR=k10temp' \
      'EXTRA_FILESYSTEMS=/volume1' \
      'SMART_DEVICES=/dev/sata1:sat,/dev/sata2:sat,/dev/sata3:sat,/dev/sata4:sat,/dev/sata5:sat,/dev/sata6:sat,/dev/sata7:sat,/dev/sata8:sat' \
      'EnvironmentFile=/volume1/@appdata/nix-system/secrets/beszel-agent.env' \
      'CAP_SYS_ADMIN' 'CAP_SYS_RAWIO' 'smartmontools' 'bin/beszel-agent'; do
      grep -qF "$want" $u || fail "missing: $want"
    done
    ! grep -q 'TOKEN=' $u || fail "token must not be in the store"
    [ -e ${hostGeneration}/wants/multi-user.target/beszel-agent.service ] || fail "not started at boot"
  '';

  assertions-reject = assert rejects [{environment.etc."passwd".text = "";}];
  assert rejects [{environment.etc."nix/../shadow".text = "";}];
  assert rejects [{environment.etc."nix//x".text = "";}];
  assert rejects [{systemd.units."../x.service".text = "";}];
  assert rejects [
    {
      dsm.tasks."Mount nix and start daemon" = {
        event = "bootup";
        script = "x";
      };
    }
  ];
  assert !(rejects [
    {
      dsm.tasks.ok = {
        event = "shutdown";
        script = "x";
      };
    }
  ]);
  assert rejects [
    {
      dsm.tasks.x = {
        event = "weekly";
        script = "x";
      };
    }
  ];
  assert rejects [{users.users.plex = {};}];
  assert !(rejects [{users.users.svc-plex = {};}]);
  assert rejects [{dsm.services.ssh.enable = false;}];
  assert !(rejects [{dsm.services.ssh.enable = true;}]);
  assert rejects [
    {
      dsm.services.ssh.settings.ssh_cipher = [
        {
          name = "aes128-ctr";
          in_use = false;
        }
      ];
    }
  ];
  assert rejects [
    {
      dsm.services.ssh.settings.ssh_kex = [
        {
          name = "curve25519-sha256";
          in_use = false;
        }
      ];
    }
  ];
  assert rejects [
    {
      dsm.services.ssh.settings.ssh_mac = [
        {
          name = "hmac-sha2-256";
          in_use = false;
        }
      ];
    }
  ];
  assert !(rejects [
    {
      dsm.services.ssh.settings.ssh_cipher = [
        {
          name = "aes128-ctr";
          in_use = true;
        }
        {
          name = "3des-cbc";
          in_use = false;
        }
      ];
    }
  ]);
  assert rejects [{dsm.services.x.settings.a = 1;}];
  assert rejects [
    {
      dsm.tasks.s = {
        event = "schedule";
        script = "x";
      };
    }
  ];
  assert rejects [
    {
      dsm.tasks.b = {
        event = "bootup";
        script = "x";
        schedule = {
          hour = 0;
          minute = 0;
        };
      };
    }
  ];
  assert rejects [
    {
      dsm.tasks.s = {
        event = "schedule";
        script = "x";
        schedule = {
          hour = 0;
          minute = 0;
          repeatMinutes = 5;
          repeatHours = 1;
        };
      };
    }
  ];
    check "assertions-reject" "";

  dsm-services-json = check "dsm-services-json" ''
    s=${genServices}/dsm-services.json
    jq -e '.smb.package == "SMBService"' $s >/dev/null || fail "smb package: $(cat $s)"
    jq -e '.smb.settings == {"smb_max_protocol": 3, "enable_samba": true}' $s >/dev/null || fail "smb settings: $(cat $s)"
    jq -e '.smb.settingsApi == {"api": "SYNO.Core.FileServ.SMB", "version": 3}' $s >/dev/null || fail "smb api: $(cat $s)"
    jq -e '.ssh.package == null and .ssh.settings.enable_ssh == true' $s >/dev/null || fail "ssh: $(cat $s)"
    jq -e '.foo.enable == false and .foo.volume == "/volume1" and .foo.package == "Foo"' $s >/dev/null || fail "foo: $(cat $s)"
    jq -e 'has("container-manager") | not' $s >/dev/null || fail "undeclared service present: $(cat $s)"
    jq -e '. == {"SynoCommunity": "https://packages.synocommunity.com/"}' ${genServices}/dsm-feeds.json >/dev/null || fail "feeds"
  '';

  dsm-schedule-json = check "dsm-schedule-json" ''
    t=${genSchedule}/dsm-tasks.json
    jq -e '.t.schedule == {"weekDays": [0,1,2,3,4,5,6], "hour": 0, "minute": 0, "repeatMinutes": null, "repeatHours": null, "lastHour": 23}' $t >/dev/null || fail "schedule: $(cat $t)"
  '';

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

  # The state says b.service is ours, but by now DSM has a real file there.
  ignores-foreign-in-state = scenario "ignores-foreign-in-state" ''
    run ${genAB}
    rm $ROOT/etc/systemd/system/b.service
    printf '[Unit]\nDescription=DSM b\n' > $ROOT/etc/systemd/system/b.service
    run ${genA}
    grep -q 'DSM b' $ROOT/etc/systemd/system/b.service || fail "DSM's b.service removed"
    ! called "systemctl stop b.service" || fail "DSM's b.service stopped"
  '';

  refuses-dsm-collision = scenario "refuses-dsm-collision" ''
    if run ${genCollidesDsm}; then fail "declaring a DSM unit name succeeded"; fi
    if run ${genCollidesTemplate}; then fail "shadowing DSM's user@.service succeeded"; fi
    [ ! -e "$ROOT/etc/systemd/system/user@.service" ] || fail "user@.service written"
  '';

  wants-foreign = scenario "wants-foreign" ''
    run ${genDropIn}
    # DSM (or a person) re-points the link; it is no longer the one we made.
    ln -sfn /etc/systemd/system/user@1027.service $ROOT/etc/systemd/system/multi-user.target.wants/user@1027.service
    run ${genA}
    [ -L $ROOT/etc/systemd/system/multi-user.target.wants/user@1027.service ] || fail "foreign wants link removed"
  '';

  etc-path-guard = scenario "etc-path-guard" ''
    run ${genA}
    jq '.etc += ["passwd", "nix/../shadow"]' $ROOT/volume1/@appdata/nix-system/state.json > s.json
    mv s.json $ROOT/volume1/@appdata/nix-system/state.json
    run ${genA}
  '';

  pending-state = scenario "pending-state" ''
    run ${genA}
    if NIX_ENV=false run ${genAB}; then fail "expected the profile step to fail"; fi
    run ${genA}
    [ ! -e $ROOT/etc/systemd/system/b.service ] || fail "b.service from the failed run leaked"
    [ ! -e $ROOT/etc/nix/old.conf ] || fail "old.conf from the failed run leaked"
  '';

  corrupt-state = scenario "corrupt-state" ''
    mkdir -p $ROOT/volume1/@appdata/nix-system
    echo '{not json' > $ROOT/volume1/@appdata/nix-system/state.json
    run ${genDaemon1}
    [ -e $ROOT/active/nix-daemon.service ] || fail "daemon not started with a corrupt state"
  '';

  default-profile-switch = scenario "default-profile-switch" ''
    run ${genProfile}
    [ "$(readlink -f $ROOT/nix/var/nix/profiles/default)" = "$(readlink -f ${genProfile}/default-profile)" ] \
      || fail "default profile points at $(readlink -f $ROOT/nix/var/nix/profiles/default), not the default-profile env"
    run ${genProfile}
    ! called_matching "^nix-env" || fail "default profile re-switched with nothing changed"
  '';

  profile-switch = scenario "profile-switch" ''
    run ${genA}
    [ "$(readlink $ROOT/nix/var/nix/profiles/potato-bunny)" = "${genA}" ] || fail "system profile not switched"
    run ${genA}
    ! called_matching '^nix-env' || fail "profile re-switched with nothing changed"
  '';

  gc-root = scenario "gc-root" ''
    if NIX_ENV=false run ${genA}; then fail "expected the profile step to fail"; fi
    [ "$(readlink $ROOT/nix/var/nix/gcroots/potato-bunny-pending)" = "${genA}" ] || fail "generation not GC-rooted before switching"
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

  daemon-started = scenario "daemon-started" ''
    run ${genDaemon1}
    called "systemctl start nix-daemon.service" || fail "daemon not started"
  '';

  # systemd reports a crash-looping simple service as active; only the socket tells.
  daemon-probe = scenario "daemon-probe" ''
    run ${genDaemon1}
    echo crashloop > $ROOT/daemon-health
    if run ${genDaemon2}; then fail "activate succeeded with a daemon that never answers"; fi
    [ "$(link nix-daemon.service)" = "${genDaemon1}/units/nix-daemon.service" ] || fail "not rolled back"
  '';

  # First activation on the NAS: the installer's daemon is linked and running.
  daemon-first-run = scenario "daemon-first-run" ''
    ln -s ${installerDaemon} $ROOT/etc/systemd/system/nix-daemon.service
    mkdir -p $ROOT/active && touch $ROOT/active/nix-daemon.service
    run ${genDaemon1}
    called "systemctl restart nix-daemon.service" || fail "installer daemon not replaced"
    [ "$(link nix-daemon.service)" = "${genDaemon1}/units/nix-daemon.service" ] || fail "not linked"
  '';

  daemon-first-run-rollback = scenario "daemon-first-run-rollback" ''
    ln -s ${installerDaemon} $ROOT/etc/systemd/system/nix-daemon.service
    mkdir -p $ROOT/active && touch $ROOT/active/nix-daemon.service
    echo crashloop > $ROOT/daemon-health
    if run ${genDaemon1}; then fail "activate succeeded with a broken daemon"; fi
    [ "$(link nix-daemon.service)" = ${installerDaemon} ] || fail "installer daemon not restored: $(link nix-daemon.service)"
  '';

  nixconf-restarts-daemon = scenario "nixconf-restarts-daemon" ''
    run ${genDaemonConf "a = 1\n"}
    run ${genDaemonConf "a = 2\n"}
    called "systemctl restart nix-daemon.service" || fail "nix.conf change did not restart the daemon"
  '';

  nixconf-rollback = scenario "nixconf-rollback" ''
    run ${genDaemonConf "a = 1\n"}
    echo crashloop > $ROOT/daemon-health
    if run ${genDaemonConf "a = 2\n"}; then fail "activate succeeded with a broken daemon"; fi
    grep -qx 'a = 1' $ROOT/etc/nix/nix.conf || fail "old nix.conf not restored"
  '';

  keeps-daemon = scenario "keeps-daemon" ''
    run ${genDaemon1}
    run ${genA}
    ! called "systemctl stop nix-daemon.service" || fail "daemon stopped"
    [ -L $ROOT/etc/systemd/system/nix-daemon.service ] || fail "daemon unlinked"
  '';

  installer-socket-removed = scenario "installer-socket-removed" ''
    mkdir -p $ROOT/etc/systemd/system/sockets.target.wants
    ln -s ${installerSocket} $ROOT/etc/systemd/system/nix-daemon.socket
    ln -s ${installerSocket} $ROOT/etc/systemd/system/sockets.target.wants/nix-daemon.socket
    run ${genDaemon1}
    [ ! -e $ROOT/etc/systemd/system/nix-daemon.socket ] || fail "installer socket left linked"
    [ ! -L $ROOT/etc/systemd/system/sockets.target.wants/nix-daemon.socket ] || fail "installer socket still wanted"
    called "systemctl stop nix-daemon.socket" || fail "installer socket not stopped"
  '';

  # A service's account must exist before the service starts.
  users-before-units = scenario "users-before-units" ''
    run ${genUserUnit}
    add=$(grep -n "^synouser --add svc-foo " $ROOT/calls | cut -d: -f1)
    start=$(grep -n "^systemctl start foo.service" $ROOT/calls | cut -d: -f1)
    [ -n "$add" ] && [ -n "$start" ] || fail "missing add or start: $(cat $ROOT/calls)"
    [ "$add" -lt "$start" ] || fail "foo.service started before svc-foo existed"
  '';

  # At boot (nothing changed) a daemon that won't come up must not keep the
  # rest of the layer down; activate still fails and leaves the state alone.
  daemon-down-others-start = scenario "daemon-down-others-start" ''
    run ${genDaemonAndA}
    rm -f $ROOT/active/a.service
    echo dead > $ROOT/daemon-health
    if run ${genDaemonAndA}; then fail "activate succeeded with a dead daemon"; fi
    called "systemctl start a.service" || fail "a.service not started while the daemon was down"
  '';

  tasks-created = scenario "tasks-created" ''
    run ${genTasks "bash /x.sh"}
    called "synowebapi create HDD db" || fail "task not created: $(cat $ROOT/calls)"
    t="$ROOT/tasks/HDD db.json"
    jq -e '.event == "bootup" and .operation == "bash /x.sh" and .enable == true and .operation_type == "script"' "$t" >/dev/null || fail "task fields: $(cat "$t")"
    jq -e '.owner == {"0": "root"} and .notify_enable == true and .notify_if_error == true and .notify_mail == "me@example.com"' "$t" >/dev/null || fail "task owner/notify: $(cat "$t")"
    jq -e '.depend_on_task == ""' "$t" >/dev/null || fail "unexpected dependency: $(cat "$t")"
  '';

  tasks-depends = scenario "tasks-depends" ''
    run ${genTaskDepends}
    jq -e '.depend_on_task == "[HDD db]"' "$ROOT/tasks/dedupe.json" >/dev/null || fail "dependency: $(cat "$ROOT/tasks/dedupe.json")"
    run ${genTaskDepends}
    ! called_matching '^synowebapi \(create\|set\) ' || fail "dependent task rewritten on an unchanged run"
  '';

  # A declared task runs as root; one DSM has under another owner is corrected.
  tasks-owner-drift = scenario "tasks-owner-drift" ''
    run ${genTasks "bash /x.sh"}
    jq '.owner = {"1027": "hawken"}' "$ROOT/tasks/HDD db.json" > o.json && mv o.json "$ROOT/tasks/HDD db.json"
    run ${genTasks "bash /x.sh"}
    called "synowebapi set HDD db" || fail "owner drift not corrected"
  '';

  # Scripts reach DSM byte for byte: real newlines, backslashes untouched.
  tasks-multiline = scenario "tasks-multiline" ''
    run ${genTasks multilineScript}
    jq -j .operation "$ROOT/tasks/HDD db.json" > got
    cmp -s ${pkgs.writeText "expected" multilineScript} got || fail "script mangled: $(od -c got | head -4)"
    run ${genTasks multilineScript}
    ! called_matching '^synowebapi set' || fail "multi-line task rewritten on an unchanged run"
  '';

  tasks-updated = scenario "tasks-updated" ''
    run ${genTasks "bash /x.sh"}
    run ${genTasks "bash /y.sh"}
    called "synowebapi set HDD db" || fail "changed task not updated"
    jq -e '.operation == "bash /y.sh"' "$ROOT/tasks/HDD db.json" >/dev/null || fail "operation not updated"
  '';

  tasks-idempotent = scenario "tasks-idempotent" ''
    run ${genTasks "bash /x.sh"}
    run ${genTasks "bash /x.sh"}
    ! called_matching '^synowebapi \(create\|set\|delete\) ' || fail "unchanged task rewritten: $(cat $ROOT/calls)"
  '';

  # Tasks are never deleted, including ones this layer used to declare.
  tasks-never-deleted = scenario "tasks-never-deleted" ''
    run ${genTasks "bash /x.sh"}
    run ${genA}
    ! called_matching '^synowebapi delete' || fail "task deleted"
    [ -f "$ROOT/tasks/HDD db.json" ] || fail "task gone"
  '';

  daemon-rollback = scenario "daemon-rollback" ''
    run ${genDaemon1}
    echo dead > $ROOT/daemon-health
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
    called "synogroup --memberadd nixbld nixbld1" || fail "nixbld1 not added"
    called "synogroup --memberadd nixbld nixbld2" || fail "nixbld2 not added"
    called "synogroup --memberadd video svc-known" || fail "extraGroups not applied"
    ! called_matching '--del' || fail "something was deleted"
  '';

  # Membership only grows: members DSM (or a person) added are never removed.
  groups-additive = scenario "groups-additive" ''
    printf 'stranger\nnixbld1\n' > $ROOT/groups/nixbld
    run ${genUsers}
    grep -qx stranger $ROOT/groups/nixbld || fail "existing member removed"
    ! called_matching '^synogroup --member ' || fail "membership replaced wholesale"
    ! called "synogroup --memberadd nixbld nixbld1" || fail "existing member re-added"
  '';

  # A user's extraGroups may name a group this generation creates.
  groups-before-users = scenario "groups-before-users" ''
    run ${genMediaGroup}
    grep -qx svc-a $ROOT/groups/media || fail "svc-a not in media"
  '';

  no-direct-account-writes = scenario "no-direct-account-writes" ''
    run ${genUsers}
    run ${genAB}
    run ${genDropIn}
  '';
}
