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
  # --memberadd still adds but exits 1 while $ROOT/memberadd-lies exists, as
  # DSM's does for administrators.
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
      --memberadd) echo "$3" >> "$f"; [ ! -e "$ROOT/memberadd-lies" ] || exit 1 ;;
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

  # DSM's web APIs, by api:
  # - SYNO.Core.EventScheduler (boot-up/shutdown tasks): tasks live in
  #   $ROOT/tasks/<name>.json as the "data" object get returns; a missing task
  #   gets success with no data; fails while $ROOT/event-fail exists. Logged
  #   as "synowebapi <method> <name>".
  # - SYNO.Core.Package.Feed: $ROOT/feeds.json, an array of {name, feed}.
  # - SYNO.Core.TaskScheduler(.Root): scheduled tasks (see below).
  # - SYNO.Core.Share(.Permission): shared folders and their grants (see below).
  # - Any other api: a settings object (see below).
  # Other APIs are logged as "synowebapi <api> <method>". Methods activate
  # must never call (deletes) exit 3.
  synowebapiStub = pkgs.writeShellScript "synowebapi" ''
    jq=${pkgs.jq}/bin/jq
    [ "$1" = --exec ] && shift
    api="" method="" name="" obj='{}'
    for arg in "$@"; do
      key=''${arg%%=*} val=''${arg#*=}
      case "$key" in
        version) ;;
        api) api=$val ;;
        method) method=$val ;;
        *) obj=$($jq -c --arg k "$key" --argjson v "$val" '. + {($k): $v}' <<<"$obj")
           [ "$key" = task_name ] && name=$($jq -r . <<<"$val") ;;
      esac
    done
    case "$api" in
      SYNO.Core.EventScheduler)
        [ ! -e "$ROOT/event-fail" ] || exit 1
        echo "synowebapi $method $name" >> "$ROOT/calls"
        f="$ROOT/tasks/$name.json"
        case "$method" in
          get) if [ -f "$f" ]; then $jq -c '{data: ., success: true}' "$f"; else echo '{"success":true}'; fi ;;
          create|set) mkdir -p "$ROOT/tasks"; echo "$obj" > "$f"; echo '{"success":true}' ;;
          delete) rm -f "$f"; echo '{"success":true}' ;;
          *) echo "synowebapi stub: unexpected $*" >&2; exit 2 ;;
        esac ;;
      SYNO.Core.Package.Feed)
        echo "synowebapi $api $method" >> "$ROOT/calls"
        f="$ROOT/feeds.json"
        [ -f "$f" ] || echo '[]' > "$f"
        case "$method" in
          list) $jq -c '{data: {items: ., total: length}, success: true}' "$f" ;;
          add) $jq -c --argjson o "$obj" '. + [$o]' "$f" > "$f.new" && mv "$f.new" "$f"; echo '{"success":true}' ;;
          delete) exit 3 ;;
          *) echo "synowebapi stub: unexpected $*" >&2; exit 2 ;;
        esac ;;
      SYNO.Core.Share)
        # Shares: $ROOT/shares/<name>.json holds what get returns.
        sname=$($jq -r '.name' <<<"$obj")
        echo "synowebapi $api $method $sname" >> "$ROOT/calls"
        f="$ROOT/shares/$sname.json"
        mkdir -p "$ROOT/shares"
        case "$method" in
          get) if [ -f "$f" ]; then $jq -c '{data: ., success: true}' "$f"; else echo '{"error":{"code":402},"success":false}'; fi ;;
          create|set)
            $jq -c --arg n "$sname" '.shareinfo | {name: $n, vol_path, desc, hidden, enable_recycle_bin, quota_value: (.share_quota | tonumber)}' <<<"$obj" > "$f"
            echo '{"success":true}' ;;
          *) exit 3 ;;
        esac ;;
      SYNO.Core.Share.Permission)
        # Grants: $ROOT/shares/<name>.<user_group_type>.json, an array of permission objects.
        sname=$($jq -r '.name' <<<"$obj")
        echo "synowebapi $api $method $sname" >> "$ROOT/calls"
        f="$ROOT/shares/$sname.$($jq -r .user_group_type <<<"$obj").json"
        mkdir -p "$ROOT/shares"
        [ -f "$f" ] || echo '[]' > "$f"
        case "$method" in
          list) $jq -c '{data: {items: ., total: length}, success: true}' "$f" ;;
          set)
            $jq -c --argjson p "$($jq -c .permissions <<<"$obj")" '(map(.name) - ($p | map(.name))) as $keep | map(select(.name as $n | $keep | index($n))) + $p' "$f" > "$f.new" && mv "$f.new" "$f"
            echo '{"success":true}' ;;
          *) exit 3 ;;
        esac ;;
      SYNO.Core.TaskScheduler | SYNO.Core.TaskScheduler.Root)
        # Scheduled tasks: $ROOT/sched/<id>.json, each the v4 get "data"
        # object plus type and real_owner.
        d="$ROOT/sched"
        mkdir -p "$d"
        id=$($jq -r '.id // empty' <<<"$obj")
        # Like DSM, v4 create/set refuse a schedule without monthly_week.
        case "$method" in create | set)
          if ! $jq -e '.schedule | has("monthly_week")' <<<"$obj" >/dev/null; then
            echo "synowebapi $api $method refused" >> "$ROOT/calls"
            echo '{"error":{"code":4800,"errors":{"msg":"monthly_week expected for v4"}},"success":false}'
            exit 0
          fi ;;
        esac
        case "$method" in
          list)
            echo "synowebapi $api list" >> "$ROOT/calls"
            if [ -e "$ROOT/sched-list-bare" ]; then
              echo '{"data":{},"success":true}'
            elif ls "$d"/*.json >/dev/null 2>&1; then
              $jq -sc '{data: {tasks: map({id, name, type, owner, real_owner, enable}), total: length}, success: true}' "$d"/*.json
            else
              echo '{"data":{"tasks":[],"total":0},"success":true}'
            fi ;;
          get)
            echo "synowebapi $api get $id" >> "$ROOT/calls"
            $jq -c '{data: ., success: true}' "$d/$id.json" ;;
          create)
            echo "synowebapi $api create $($jq -r .name <<<"$obj")" >> "$ROOT/calls"
            id=$(( $(ls "$d" | sed 's/\.json$//' | sort -n | tail -1) + 1 ))
            $jq -c --argjson id "$id" '. + {id: $id, real_owner: "root"}' <<<"$obj" > "$d/$id.json"
            echo '{"success":true}' ;;
          set)
            echo "synowebapi $api set $id" >> "$ROOT/calls"
            $jq -c --argjson o "$obj" '. + $o' "$d/$id.json" > "$d/$id.new" && mv "$d/$id.new" "$d/$id.json"
            echo '{"success":true}' ;;
          *) exit 3 ;;
        esac ;;
      *)
        # Any other API is one settings object, $ROOT/settings/<api>.json;
        # set merges the given keys into it.
        echo "synowebapi $api $method" >> "$ROOT/calls"
        f="$ROOT/settings/$api.json"
        mkdir -p "$ROOT/settings"
        [ -f "$f" ] || echo '{}' > "$f"
        case "$method" in
          get) $jq -c '{data: ., success: true}' "$f" ;;
          set) $jq -c --argjson o "$obj" '. + $o' "$f" > "$f.new" && mv "$f.new" "$f"; echo '{"success":true}' ;;
          *) echo "synowebapi stub: unexpected $*" >&2; exit 2 ;;
        esac ;;
    esac
  '';

  # Package Center: packages are $ROOT/pkgs/<id>, holding "on" or "off". Any
  # command on an id with $ROOT/pkg-fail/<id> present fails; list fails while
  # $ROOT/pkg-list-fail exists.
  synopkgStub = pkgs.writeShellScript "synopkg" ''
    echo "synopkg $*" >> "$ROOT/calls"
    id=''${2:-}
    [ -z "$id" ] || [ ! -e "$ROOT/pkg-fail/$id" ] || exit 1
    case "$1" in
      list) [ "$2" = --name ] || exit 2; [ ! -e "$ROOT/pkg-list-fail" ] || exit 1; ls "$ROOT/pkgs" 2>/dev/null || true ;;
      is_onoff) [ "$(cat "$ROOT/pkgs/$id" 2>/dev/null)" = on ] ;;
      install_from_server) mkdir -p "$ROOT/pkgs"; echo off > "$ROOT/pkgs/$id" ;;
      start) [ -e "$ROOT/pkgs/$id" ] && echo on > "$ROOT/pkgs/$id" ;;
      stop) [ -e "$ROOT/pkgs/$id" ] && echo off > "$ROOT/pkgs/$id" ;;
      *) echo "synopkg stub: unexpected $*" >&2; exit 2 ;;
    esac
  '';

  # Accounts all have uid 1234; chown only logs (the sandbox can't chown).
  idStub = pkgs.writeShellScript "id" ''
    [ "$1" = -u ] || exit 2
    grep -qx "$2" "$ROOT/known-users" && echo 1234
  '';
  chownStub = pkgs.writeShellScript "chown" ''
    echo "chown $*" >> "$ROOT/calls"
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

      export SYSTEMCTL=${systemctlStub} SYNOUSER=${synouserStub} SYNOGROUP=${synogroupStub} SYNOWEBAPI=${synowebapiStub} SYNOPKG=${synopkgStub}
      export DAEMON_PROBE=${probeStub} NIX_ENV=${nixEnvStub} ACTIVATE_DAEMON_TIMEOUT=1 ID=${idStub} CHOWN=${chownStub}
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
  genFoo = mkGeneration [
    {
      dsm.services.foo = {
        package = "Foo";
        enable = true;
      };
    }
  ];
  genFooAndTask = mkGeneration [
    {
      dsm.services.foo = {
        package = "Foo";
        enable = true;
      };
      dsm.tasks."HDD db" = {
        event = "bootup";
        script = "bash /x.sh";
      };
    }
  ];
  genPkg = enable:
    mkGeneration [
      {
        dsm.services.foo =
          {package = "Foo";}
          // pkgs.lib.optionalAttrs (enable != null) {inherit enable;};
      }
    ];
  genPkgAB = mkGeneration [
    {
      dsm.services.a = {
        package = "A";
        enable = true;
      };
      dsm.services.b = {
        package = "B";
        enable = true;
      };
    }
  ];
  genFeed = mkGeneration [{dsm.packageSources.SynoCommunity = "https://packages.synocommunity.com/";}];
  genSmb = mkGeneration [
    {
      dsm.services.smb.settings = {
        smb_max_protocol = 3;
        workgroup = "W";
      };
    }
  ];
  genListSetting = mkGeneration [
    {
      dsm.services.x = {
        settingsApi = {
          api = "SYNO.Test.List";
          version = 1;
        };
        settings.items = [{name = "a";} {name = "b";}];
      };
    }
  ];
  genSched = minute:
    mkGeneration [
      {
        dsm.tasks."tailscale update" = {
          event = "schedule";
          script = "tailscale update --yes";
          schedule = {
            hour = 0;
            inherit minute;
          };
        };
      }
    ];
  genSchedRsync = mkGeneration [
    {
      dsm.tasks."rsync.net" = {
        event = "schedule";
        script = "rsync";
        schedule = {
          hour = 3;
          minute = 0;
        };
      };
      dsm.tasks.other = {
        event = "schedule";
        script = "other";
        schedule = {
          hour = 4;
          minute = 0;
        };
      };
    }
  ];
  genSchedDays = mkGeneration [
    {
      dsm.tasks.t = {
        event = "schedule";
        script = "x";
        schedule = {
          weekDays = [1 0];
          hour = 0;
          minute = 0;
        };
      };
    }
  ];
  genSmbTypo = mkGeneration [{dsm.services.smb.settings.smb_max_protcol = 3;}];
  genTaskAndA = mkGeneration [
    {
      systemd.units."a.service" = unit "[Service]\nExecStart=/bin/a\n";
      dsm.tasks."HDD db" = {
        event = "bootup";
        script = "x";
      };
    }
  ];
  genShare = quota:
    mkGeneration [
      {
        dsm.shares.mbx-cache = {
          volume = "/volume2";
          description = "mbx build cache";
          hidden = true;
          recycleBin = false;
          quotaMB = quota;
          users.svc-x = "rw";
        };
      }
    ];
  genKeys = keys:
    mkGeneration [
      {
        users.users.svc-cache = {
          description = "cache";
          authorizedKeys = keys;
        };
      }
    ];
  keyA = "restrict,command=\"/x --stdio\" ssh-ed25519 AAAAA host-a";
  keyB = "restrict,command=\"/x --stdio\" ssh-ed25519 BBBBB host-b";
  # The store GC timer's script, with df and nix-store stubbed; `script` checks $PWD/calls.
  storeGc = name: freeBytes: script:
    check "store-gc-${name}" ''
      mkdir bin
      printf '#!${pkgs.runtimeShell}\necho Avail\necho ${toString freeBytes}\n' > bin/df
      printf '#!${pkgs.runtimeShell}\necho "nix-store $*" >> %s/calls\n' "$PWD" > bin/nix-store
      chmod +x bin/*
      : > calls
      PATH=$PWD/bin:$PATH GC_PATH=/volume1 MIN_FREE=322122547200 MAX_FREE=644245094400 NIX_STORE=$PWD/bin/nix-store \
        ${pkgs.bash}/bin/bash ${../../hosts/potato-bunny/store-gc.sh}
      ${script}
    '';
  # mbx-cache's eviction script on a scratch dir: blobs of 100 bytes, HIGH/LOW
  # in bytes, a stub mbx-cache logging its arguments. `setup` fills ./data.
  evict = name: high: low: setup: script:
    check "evict-${name}" ''
      mkdir data
      blob() { head -c 100 /dev/zero > "data/$1"; touch -d "$2" "data/$1"; }
      ${setup}
      printf '#!${pkgs.runtimeShell}\necho "mbx-cache $*" >> %s/calls\n' "$PWD" > mbx; chmod +x mbx
      : > calls
      DATA_DIR=$PWD/data HIGH_BYTES=${toString high} LOW_BYTES=${toString low} MBX_CACHE=$PWD/mbx \
        PATH=${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.gawk}/bin \
        ${pkgs.bash}/bin/bash ${../../hosts/potato-bunny/mbx-cache-evict.sh}
      ${script}
    '';
  genShareGroups = mkGeneration [
    {
      dsm.shares.mbx-cache = {
        volume = "/volume2";
        description = "mbx build cache";
        hidden = true;
        recycleBin = false;
        quotaMB = 500000;
        users.svc-x = "rw";
        groups.administrators = "none";
      };
    }
  ];
  # The one-time copy of the Synology package's Tailscale state into the nix
  # daemon's state dir; `setup` fills ./old (and maybe ./new).
  tsMigrate = name: setup: script:
    check "tailscale-migrate-${name}" ''
      mkdir old
      ${setup}
      printf '#!${pkgs.runtimeShell}\necho "chown $*" >> %s/calls\n' "$PWD" > chown; chmod +x chown
      : > calls
      CHOWN=$PWD/chown PATH=${pkgs.coreutils}/bin:${pkgs.findutils}/bin \
        ${pkgs.bash}/bin/bash ${../../hosts/potato-bunny/tailscale-migrate.sh} $PWD/old $PWD/new
      ${script}
    '';
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
    jq -e '.smb.settings.workgroup == "POTATOBUNNY" and .ssh.settings.enable_ssh == true and .syncthing.package == "syncthing"' $g/dsm-services.json >/dev/null ||
      fail "dsm services: $(cat $g/dsm-services.json)"
    jq -e '."tailscale update".event == "schedule"' $g/dsm-tasks.json >/dev/null || fail "tailscale update task"
    jq -e '.SynoCommunity' $g/dsm-feeds.json >/dev/null || fail "SynoCommunity feed"
    for host in INRtF1Gu IKaiGtVc IEZW19gG; do
      jq -e --arg h "$host" '.users."svc-nixcache".authorizedKeys | any(startswith("restrict,command=\"/nix/var/nix/profiles/default/bin/nix-daemon --stdio\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA" + $h))' $g/users.json >/dev/null ||
        fail "svc-nixcache key $host: $(jq -c '.users."svc-nixcache"' $g/users.json)"
    done
    jq -e '.users."svc-nixcache".extraGroups == ["administrators"]' $g/users.json >/dev/null || fail "svc-nixcache groups"
    grep -q 'Techcyte-DGQJV434PF:FDqhahy007nFE2T8Cj5sBu7uacsP5N9V9dbuERDeeSc=' $g/etc/nix/nix.conf || fail "Mac signing key not trusted"
    [ -e $g/wants/timers.target/nix-store-gc.timer ] || fail "store GC timer not wanted by timers.target"
    [ ! -e $g/wants/multi-user.target/nix-store-gc.service ] || fail "store GC service started at boot"
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
  assert rejects [{dsm.services.ssh.settings.enable_ssh = false;}];
  assert rejects [{dsm.services.x.enable = true;}];
  assert !(rejects [{dsm.services.smb.enable = true;}]);
  assert !(rejects [{dsm.services.ssh.enable = true;}]);
  # DSM's get returns these as [{name, in_use, ...}] but set takes plain name
  # lists, so a declared value could never compare equal.
  assert rejects [
    {
      dsm.services.ssh.settings.ssh_cipher = [
        {
          name = "aes128-ctr";
          in_use = true;
        }
      ];
    }
  ];
  assert rejects [{dsm.services.ssh.settings.ssh_kex = ["curve25519-sha256"];}];
  assert rejects [{dsm.services.ssh.settings.ssh_mac = ["hmac-sha2-256"];}];
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

  # At boot, DSM is still starting its own packages: leave them to it.
  boot-skips-dsm = scenario "boot-skips-dsm" ''
    : > $ROOT/calls
    ${genFoo}/bin/activate --root "$ROOT" --boot
    ! called_matching '^synopkg' || fail "package step ran at boot: $(cat $ROOT/calls)"
  '';

  dry-run-read-only = scenario "dry-run-read-only" ''
    : > $ROOT/calls
    ${genFooAndTask}/bin/activate --root "$ROOT" --dry-run > out || fail "dry run failed"
    grep -q '^would: create DSM task "HDD db"' out || fail "task change not shown: $(cat out)"
    [ ! -e $ROOT/volume1/@appdata/nix-system/state.json ] || fail "state written"
    [ ! -e $ROOT/nix/var/nix/gcroots/potato-bunny-pending ] || fail "gc root created"
    ! called_matching '^synowebapi \(create\|set\)' || fail "DSM changed: $(cat $ROOT/calls)"
    ! called_matching '^synopkg \(install_from_server\|start\|stop\)' || fail "package changed: $(cat $ROOT/calls)"
    ! called_matching '^systemctl \(start\|restart\|stop\|daemon-reload\)' || fail "units touched: $(cat $ROOT/calls)"
    ! called_matching '^nix-env' || fail "profile switched"
    [ ! -e $ROOT/etc/systemd/system/multi-user.target.wants ] || fail "wants linked"
  '';

  dry-run-clean = scenario "dry-run-clean" ''
    run ${genTasks "bash /x.sh"}
    ${genTasks "bash /x.sh"}/bin/activate --root "$ROOT" --dry-run > out || fail "dry run failed"
    grep -qx 'no DSM changes' out || fail "expected no changes: $(cat out)"
  '';

  boot-task-flag = check "boot-task-flag" ''
    grep -q 'activate --boot ' ${../../hosts/potato-bunny/boot-task.sh} || fail "boot task does not pass --boot"
  '';

  pkg-installed-and-started = scenario "pkg-installed-and-started" ''
    run ${genPkg true}
    called "synopkg install_from_server Foo /volume1" || fail "not installed: $(cat $ROOT/calls)"
    called "synopkg start Foo" || fail "not started: $(cat $ROOT/calls)"
    [ "$(cat $ROOT/pkgs/Foo)" = on ] || fail "Foo not running"
  '';

  pkg-idempotent = scenario "pkg-idempotent" ''
    run ${genPkg true}
    run ${genPkg true}
    ! called_matching '^synopkg \(install_from_server\|start\|stop\)' || fail "unchanged package touched: $(cat $ROOT/calls)"
  '';

  # enable = false stops a package; nothing is ever uninstalled.
  pkg-disable-stops-not-uninstalls = scenario "pkg-disable-stops-not-uninstalls" ''
    mkdir -p $ROOT/pkgs && echo on > $ROOT/pkgs/Foo
    run ${genPkg false}
    called "synopkg stop Foo" || fail "not stopped: $(cat $ROOT/calls)"
    ! called_matching uninstall || fail "uninstalled"
    [ -e $ROOT/pkgs/Foo ] || fail "Foo gone"
  '';

  pkg-null-untouched = scenario "pkg-null-untouched" ''
    mkdir -p $ROOT/pkgs && echo off > $ROOT/pkgs/Foo
    run ${genPkg null}
    ! called_matching '^synopkg \(install_from_server\|start\|stop\)' || fail "hands-off package touched: $(cat $ROOT/calls)"
  '';

  # One failing package is reported; the others, profiles and state still advance.
  pkg-failure-isolated = scenario "pkg-failure-isolated" ''
    mkdir -p $ROOT/pkg-fail && touch $ROOT/pkg-fail/A
    if run ${genPkgAB}; then fail "activate succeeded although A failed"; fi
    called "synopkg start B" || fail "B not started: $(cat $ROOT/calls)"
    [ "$(readlink $ROOT/nix/var/nix/profiles/potato-bunny)" = ${genPkgAB} ] || fail "profile not switched"
    jq -e --arg g ${genPkgAB} '.generation == $g' $ROOT/volume1/@appdata/nix-system/state.json >/dev/null || fail "state not advanced"
  '';

  feeds-added = scenario "feeds-added" ''
    run ${genFeed}
    called "synowebapi SYNO.Core.Package.Feed add" || fail "feed not added: $(cat $ROOT/calls)"
    jq -e '. == [{"name": "SynoCommunity", "feed": "https://packages.synocommunity.com/"}]' $ROOT/feeds.json >/dev/null || fail "feeds: $(cat $ROOT/feeds.json)"
    run ${genFeed}
    ! called "synowebapi SYNO.Core.Package.Feed add" || fail "feed added twice"
  '';

  feeds-foreign-kept = scenario "feeds-foreign-kept" ''
    echo '[{"name": "Other", "feed": "https://example.com/"}]' > $ROOT/feeds.json
    run ${genFeed}
    jq -e 'map(.name) == ["Other", "SynoCommunity"]' $ROOT/feeds.json >/dev/null || fail "feeds: $(cat $ROOT/feeds.json)"
    ! called_matching 'Feed delete' || fail "feed deleted"
  '';

  settings-applied = scenario "settings-applied" ''
    mkdir -p $ROOT/settings
    echo '{"smb_max_protocol": 2, "workgroup": "W", "enable_symlink": true}' > $ROOT/settings/SYNO.Core.FileServ.SMB.json
    run ${genSmb}
    called "synowebapi SYNO.Core.FileServ.SMB set" || fail "not set: $(cat $ROOT/calls)"
    jq -e '. == {"smb_max_protocol": 3, "workgroup": "W", "enable_symlink": true}' $ROOT/settings/SYNO.Core.FileServ.SMB.json >/dev/null ||
      fail "settings: $(cat $ROOT/settings/SYNO.Core.FileServ.SMB.json)"
  '';

  settings-idempotent = scenario "settings-idempotent" ''
    mkdir -p $ROOT/settings && echo '{"smb_max_protocol": 2, "workgroup": "W"}' > $ROOT/settings/SYNO.Core.FileServ.SMB.json
    run ${genSmb}
    run ${genSmb}
    ! called "synowebapi SYNO.Core.FileServ.SMB set" || fail "unchanged settings set again"
  '';

  settings-dry-run-diff = scenario "settings-dry-run-diff" ''
    mkdir -p $ROOT/settings
    echo '{"smb_max_protocol": 2, "workgroup": "W"}' > $ROOT/settings/SYNO.Core.FileServ.SMB.json
    ${genSmb}/bin/activate --root "$ROOT" --dry-run > out
    grep -qx 'would: set smb: smb_max_protocol 2 -> 3' out || fail "diff not shown: $(cat out)"
    ! grep -q workgroup out || fail "unchanged key shown: $(cat out)"
  '';

  # Values compare as JSON, so lists and objects don't look changed every run.
  settings-list-values = scenario "settings-list-values" ''
    mkdir -p $ROOT/settings && echo '{"items": []}' > $ROOT/settings/SYNO.Test.List.json
    run ${genListSetting}
    called "synowebapi SYNO.Test.List set" || fail "not set"
    run ${genListSetting}
    ! called "synowebapi SYNO.Test.List set" || fail "list setting set again"
  '';

  sched-created = scenario "sched-created" ''
    run ${genSched 0}
    called "synowebapi SYNO.Core.TaskScheduler.Root create tailscale update" || fail "not created: $(cat $ROOT/calls)"
    t=$(ls $ROOT/sched/*.json)
    jq -e '.name == "tailscale update" and .owner == "root" and .enable == true and .type == "script"' $t >/dev/null || fail "task: $(cat $t)"
    jq -e '.extra.script == "tailscale update --yes" and .extra.notify_enable == false' $t >/dev/null || fail "extra: $(cat $t)"
    jq -e '.schedule | .date_type == 0 and .week_day == "0,1,2,3,4,5,6" and .hour == 0 and .minute == 0
      and .repeat_hour == 0 and .repeat_min == 0 and .last_work_hour == 0' $t >/dev/null || fail "schedule: $(cat $t)"
  '';

  sched-idempotent = scenario "sched-idempotent" ''
    run ${genSched 0}
    run ${genSched 0}
    ! called_matching 'TaskScheduler.* \(create\|set\)' || fail "unchanged task rewritten: $(cat $ROOT/calls)"
  '';

  sched-updated = scenario "sched-updated" ''
    run ${genSched 0}
    id=$(jq .id $ROOT/sched/*.json)
    run ${genSched 30}
    called "synowebapi SYNO.Core.TaskScheduler.Root set $id" || fail "not updated: $(cat $ROOT/calls)"
    jq -e '.schedule.minute == 30' $ROOT/sched/$id.json >/dev/null || fail "minute: $(cat $ROOT/sched/$id.json)"
    [ "$(ls $ROOT/sched | wc -l)" = 1 ] || fail "task duplicated"
  '';

  # DSM task names aren't unique: two matching script tasks are an error, not a guess.
  sched-ambiguous = scenario "sched-ambiguous" ''
    mkdir -p $ROOT/sched
    for i in 1 2; do
      echo "{\"id\": $i, \"name\": \"rsync.net\", \"type\": \"script\", \"owner\": \"root\", \"real_owner\": \"root\", \"enable\": true, \"extra\": {\"script\": \"x$i\"}, \"schedule\": {}}" > $ROOT/sched/$i.json
    done
    cp -a $ROOT/sched before
    if run ${genSchedRsync}; then fail "ambiguous task accepted"; fi
    for i in 1 2; do cmp -s before/$i.json $ROOT/sched/$i.json || fail "task $i changed"; done
    called "synowebapi SYNO.Core.TaskScheduler.Root create other" || fail "other task not applied: $(cat $ROOT/calls)"
  '';

  sched-ignores-other-types = scenario "sched-ignores-other-types" ''
    mkdir -p $ROOT/sched
    echo '{"id": 1, "name": "rsync.net", "type": "custom", "owner": "root", "real_owner": "root", "enable": true}' > $ROOT/sched/1.json
    cp $ROOT/sched/1.json before.json
    run ${genSchedRsync}
    called "synowebapi SYNO.Core.TaskScheduler.Root create rsync.net" || fail "script task not created: $(cat $ROOT/calls)"
    cmp -s before.json $ROOT/sched/1.json || fail "custom task changed"
  '';

  sched-never-deleted = scenario "sched-never-deleted" ''
    run ${genSched 0}
    run ${genA}
    [ "$(ls $ROOT/sched | wc -l)" = 1 ] || fail "task deleted"
    ! called_matching 'TaskScheduler.* delete' || fail "delete called"
  '';

  sched-not-event = scenario "sched-not-event" ''
    run ${genSched 0}
    ! called_matching '^synowebapi \(get\|create\|set\) tailscale update' || fail "scheduled task sent to EventScheduler: $(cat $ROOT/calls)"
  '';

  # The dry run shows package changes, not only task and settings changes.
  dry-run-shows-packages = scenario "dry-run-shows-packages" ''
    ${genPkg true}/bin/activate --root "$ROOT" --dry-run > out
    grep -qx 'would: install Foo (foo) on /volume1' out || fail "install not shown: $(cat out)"
    grep -qx 'would: start Foo (foo)' out || fail "start not shown: $(cat out)"
    mkdir -p $ROOT/pkgs && echo on > $ROOT/pkgs/Foo
    ${genPkg false}/bin/activate --root "$ROOT" --dry-run > out
    grep -qx 'would: stop Foo (foo)' out || fail "stop not shown: $(cat out)"
  '';

  # If DSM can't list installed packages, nothing is (re)installed, started or
  # stopped on a guess.
  pkg-list-failure = scenario "pkg-list-failure" ''
    mkdir -p $ROOT/pkgs && echo on > $ROOT/pkgs/Foo
    touch $ROOT/pkg-list-fail
    if run ${genPkg true}; then fail "activate succeeded although listing packages failed"; fi
    ! called_matching '^synopkg \(install_from_server\|start\|stop\)' || fail "acted on a failed list: $(cat $ROOT/calls)"
  '';

  # A fresh DSM may answer list with no tasks array at all.
  sched-list-bare = scenario "sched-list-bare" ''
    touch $ROOT/sched-list-bare
    run ${genSched 0}
    called "synowebapi SYNO.Core.TaskScheduler.Root create tailscale update" || fail "not created: $(cat $ROOT/calls)"
  '';

  # A failed activation still syncs the boot task first and activates
  # home-manager, then the deploy fails.
  deploy-continues = check "deploy-continues" ''
    mkdir -p repo/scripts repo/hosts/potato-bunny bin
    cp ${../../scripts/deploy-potato-bunny.sh} repo/scripts/deploy-potato-bunny.sh
    cp ${../../hosts/potato-bunny/boot-task.sh} repo/hosts/potato-bunny/boot-task.sh
    export CALLS=$PWD/calls
    printf '#!${pkgs.runtimeShell}\n[ "$1" = build ] && printf "/nix/store/sys\\n/nix/store/home\\n"; exit 0\n' > bin/nix
    printf '#!${pkgs.runtimeShell}\necho "ssh $*" >> "$CALLS"\ncase "$*" in *"/nix/store/sys/bin/activate"*) exit 1 ;; esac\ncat >/dev/null\n' > bin/ssh
    printf '#!${pkgs.runtimeShell}\necho builder\n' > bin/hostname
    chmod +x bin/*
    if PATH=$PWD/bin:${pkgs.coreutils}/bin:${pkgs.bash}/bin bash repo/scripts/deploy-potato-bunny.sh; then fail "deploy succeeded although activate failed"; fi
    grep -q '/nix/store/home/activate' calls || fail "home-manager not activated: $(cat calls)"
    boot=$(grep -n 'sudo bash -s' calls | cut -d: -f1)
    act=$(grep -n '/nix/store/sys/bin/activate' calls | cut -d: -f1)
    [ -n "$boot" ] && [ "$boot" -lt "$act" ] || fail "boot task not synced before activate: $(cat calls)"
  '';

  # DSM keeps week days sorted; declared order doesn't matter.
  sched-weekdays-order = scenario "sched-weekdays-order" ''
    run ${genSchedDays}
    jq -e '.schedule.week_day == "0,1"' $ROOT/sched/*.json >/dev/null || fail "week_day: $(cat $ROOT/sched/*.json)"
    run ${genSchedDays}
    ! called_matching 'TaskScheduler.* set' || fail "re-set every run"
  '';

  # A declared key DSM doesn't have is a mistake to report, not to send forever.
  settings-unknown-key = scenario "settings-unknown-key" ''
    mkdir -p $ROOT/settings
    echo '{"smb_max_protocol": 3}' > $ROOT/settings/SYNO.Core.FileServ.SMB.json
    if run ${genSmbTypo}; then fail "unknown key accepted"; fi
    ! called "synowebapi SYNO.Core.FileServ.SMB set" || fail "unknown key sent"
  '';

  # DSM's API failing for a boot-up task doesn't keep the units down.
  tasks-get-failure = scenario "tasks-get-failure" ''
    touch $ROOT/event-fail
    if run ${genTaskAndA}; then fail "activate succeeded although DSM failed"; fi
    called "systemctl start a.service" || fail "a.service not started: $(cat $ROOT/calls)"
  '';

  share-created = scenario "share-created" ''
    run ${genShare 500000}
    called "synowebapi SYNO.Core.Share create mbx-cache" || fail "not created: $(cat $ROOT/calls)"
    jq -e '. == {"name": "mbx-cache", "vol_path": "/volume2", "desc": "mbx build cache", "hidden": true, "enable_recycle_bin": false, "quota_value": 500000}' $ROOT/shares/mbx-cache.json >/dev/null ||
      fail "share: $(cat $ROOT/shares/mbx-cache.json)"
    jq -e '.[] | select(.name == "svc-x") | .is_writable == true and .is_readonly == false and .is_deny == false' $ROOT/shares/mbx-cache.local_user.json >/dev/null ||
      fail "grant: $(cat $ROOT/shares/mbx-cache.local_user.json)"
  '';

  share-idempotent = scenario "share-idempotent" ''
    run ${genShare 500000}
    run ${genShare 500000}
    ! called_matching 'SYNO.Core.Share.* \(create\|set\)' || fail "unchanged share rewritten: $(cat $ROOT/calls)"
  '';

  share-updated = scenario "share-updated" ''
    run ${genShare 500000}
    run ${genShare 600000}
    called "synowebapi SYNO.Core.Share set mbx-cache" || fail "not updated: $(cat $ROOT/calls)"
    jq -e '.quota_value == 600000' $ROOT/shares/mbx-cache.json >/dev/null || fail "quota: $(cat $ROOT/shares/mbx-cache.json)"
  '';

  # Undeclared shares and grants stay as DSM has them; nothing is deleted.
  share-foreign-untouched = scenario "share-foreign-untouched" ''
    mkdir -p $ROOT/shares
    echo '{"name": "media", "vol_path": "/volume1", "desc": "", "hidden": false, "enable_recycle_bin": true, "quota_value": 0}' > $ROOT/shares/media.json
    echo '[{"name": "hawken", "is_readonly": true, "is_writable": false, "is_deny": false, "is_custom": false}]' > $ROOT/shares/mbx-cache.local_user.json
    cp $ROOT/shares/media.json media.before
    run ${genShare 500000}
    cmp -s media.before $ROOT/shares/media.json || fail "undeclared share changed"
    jq -e 'any(.[]; .name == "hawken" and .is_readonly == true)' $ROOT/shares/mbx-cache.local_user.json >/dev/null || fail "undeclared grant changed: $(cat $ROOT/shares/mbx-cache.local_user.json)"
    ! called_matching 'Share.* delete' || fail "delete called"
  '';

  dry-run-shows-share = scenario "dry-run-shows-share" ''
    ${genShare 500000}/bin/activate --root "$ROOT" --dry-run > out
    grep -qx 'would: create share mbx-cache on /volume2' out || fail "share not shown: $(cat out)"
    [ ! -e $ROOT/shares/mbx-cache.json ] || fail "dry run created the share"
  '';

  authorized-keys-written = scenario "authorized-keys-written" ''
    # DSM gives new homes an inherited ACL, which its sshd rejects for key
    # login ("bad ACL permission"); plain 0755, like hawken's, is accepted.
    mkdir -p $ROOT/var/services/homes/svc-cache && chmod 0711 $ROOT/var/services/homes/svc-cache
    run ${genKeys [keyA keyB]}
    f=$ROOT/var/services/homes/svc-cache/.ssh/authorized_keys
    printf '%s\n' ${pkgs.lib.escapeShellArg keyA} ${pkgs.lib.escapeShellArg keyB} > want
    cmp -s want $f || fail "content: $(cat $f)"
    [ "$(stat -c %a $f)" = 600 ] || fail "file mode $(stat -c %a $f)"
    [ "$(stat -c %a $(dirname $f))" = 700 ] || fail "dir mode"
    [ "$(stat -c %a $ROOT/var/services/homes/svc-cache)" = 755 ] || fail "home mode $(stat -c %a $ROOT/var/services/homes/svc-cache)"
    called_matching "^chown 1234:100 .*/svc-cache .*/.ssh $f\$" || fail "not chowned to the account: $(cat $ROOT/calls)"
  '';

  authorized-keys-idempotent = scenario "authorized-keys-idempotent" ''
    run ${genKeys [keyA]}
    f=$ROOT/var/services/homes/svc-cache/.ssh/authorized_keys
    touch -d '2001-01-01' $f
    run ${genKeys [keyA]}
    [ "$(stat -c %Y $f)" = "$(date -d 2001-01-01 +%s)" ] || fail "unchanged file rewritten"
  '';

  authorized-keys-replaced = scenario "authorized-keys-replaced" ''
    run ${genKeys [keyA keyB]}
    run ${genKeys [keyB]}
    f=$ROOT/var/services/homes/svc-cache/.ssh/authorized_keys
    ! grep -q AAAAA $f || fail "removed key still present"
    grep -q BBBBB $f || fail "kept key missing"
  '';

  store-gc-noop = storeGc "noop" 429496729600 ''
    [ ! -s calls ] || fail "GC ran with 400 GiB free: $(cat calls)"
  '';

  store-gc-frees = storeGc "frees" 107374182400 ''
    grep -qx 'nix-store --gc --max-freed 536870912000' calls || fail "GC call: $(cat calls)"
  '';

  evict-under-high =
    evict "under-high" 350 200 ''
      blob a "30 days ago"; blob b "20 days ago"; blob c "10 days ago"
    '' ''
      [ "$(ls data | wc -l)" = 3 ] || fail "deleted below the high mark"
      [ ! -s calls ] || fail "swept below the high mark"
    '';

  evict-to-low =
    evict "to-low" 350 200 ''
      blob a "30 days ago"; blob b "20 days ago"; blob c "10 days ago"; blob d "1 hour ago"
    '' ''
      [ "$(ls data | tr '\n' ' ')" = "c d " ] || fail "kept: $(ls data)"
      grep -qx 'mbx-cache --sweep-metadata-older-than-days 11' calls || fail "sweep: $(cat calls)"
    '';

  # Only regular files count or go: directories stay, symlinks aren't followed.
  evict-only-files =
    evict "only-files" 350 200 ''
      mkdir data/sub; blob sub/a "30 days ago"; blob b "20 days ago"
      head -c 1000 /dev/zero > outside; ln -s "$PWD/outside" data/link
    '' ''
      [ -d data/sub ] && [ -e data/sub/a ] && [ -e data/b ] || fail "deleted under the high mark: $(find data)"
      [ "$(stat -c %s outside)" = 1000 ] && [ -L data/link ] || fail "symlink target touched"
    '';

  mbx-units = check "mbx-units" ''
    u=${hostGeneration}/units
    grep -q 'port=5433' $u/nix-postgresql.service || fail "postgres port"
    grep -q '/run/nix-postgresql' $u/nix-postgresql.service || fail "postgres socket dir"
    ! grep -q 5432 $u/nix-postgresql.service $u/mbx-cache.service || fail "DSM's postgres port referenced"
    grep -qx 'Requires=nix-postgresql.service' $u/mbx-cache.service || fail "mbx-cache doesn't require postgres"
    grep -q 'host=/run/nix-postgresql' $u/mbx-cache.service || fail "mbx-cache database URL"
    grep -q 'MBX_CACHE_DATA_DIR=/volume2/mbx-cache' $u/mbx-cache.service || fail "mbx data dir"
    serve=$(sed -n 's/^ExecStart=//p' $u/mbx-cache-serve.service)
    grep -q 'https=8443' $serve || fail "serve port"
    ! grep -Eq 'https=443( |$)' $serve || fail "serve touches 443"
    [ -e ${hostGeneration}/wants/timers.target/mbx-cache-evict.timer ] || fail "evict timer not wanted"
    jq -e '."mbx-cache" | .volume == "/volume2" and .quotaMB == 500000 and .hidden and (.recycleBin | not) and .users == {"svc-mbx-cache": "rw"}' ${hostGeneration}/dsm-shares.json >/dev/null ||
      fail "share: $(cat ${hostGeneration}/dsm-shares.json)"
    if grep -lE '^(DynamicUser|StateDirectory|LoadCredential|ProtectKernel[A-Za-z]*|RandomizedDelaySec|ProtectClock|ProcSubset|ProtectProc)=' $u/* $u/*/* 2>/dev/null; then
      fail "directives systemd 219 doesn't know"
    fi
  '';

  watch-units = check "watch-units" ''
    g=${hostGeneration}
    s=$g/units/host-watch-nutmeg.service
    [ -f $s ] && [ -f "$g/units/notify-failure@.service" ] && [ -f $g/units/host-watch-nutmeg.timer ] || fail "units missing"
    [ -e $g/wants/timers.target/host-watch-nutmeg.timer ] || fail "timer not wanted by timers.target"
    [ ! -e $g/wants/multi-user.target/host-watch-nutmeg.service ] || fail "check started at boot"
    [ ! -e "$g/wants/multi-user.target/notify-failure@.service" ] || fail "template wanted"
    grep -qx 'OnFailure=notify-failure@%n.service' $s || fail "no OnFailure"
    probe=$(sed -n 's/^ExecStart=//p' $s)
    grep -q '100.70.139.99' $probe && grep -q ' 22 ' $probe || fail "probe target: $(cat $probe)"
    notify=$(sed -n 's/^ExecStart=//p' "$g/units/notify-failure@.service" | cut -d' ' -f1)
    grep -q '/usr/bin/journalctl' $notify && grep -q 'potato-bunny' $notify || fail "notify script: $(cat $notify)"
    grep -q 'telegram-notify.env' "$g/units/notify-failure@.service" || fail "token file"
  '';

  # DSM's synogroup can report failure for an add that worked: the membership
  # decides, and the users after it are still created.
  memberadd-false-failure = scenario "memberadd-false-failure" ''
    touch $ROOT/memberadd-lies
    run ${genUsers}
    grep -qx svc-known $ROOT/groups/video || fail "member not added"
    called_matching '^synouser --add svc-test ' || fail "later user not created: $(cat $ROOT/calls)"
  '';

  # nixpkgs' runuser needs PAM, which DSM refuses ("Failure setting user credentials").
  no-runuser = check "no-runuser" ''
    for u in ${hostGeneration}/units/*.service; do
      for s in $(sed -n 's/^Exec[A-Za-z]*=//p' $u | cut -d' ' -f1); do
        [ -f "$s" ] && ! grep -q runuser "$s" || [ ! -f "$s" ] || fail "$u runs runuser via $s"
      done
    done
  '';

  # A listing bigger than a pipe buffer: taking its first line must not kill
  # the script (SIGPIPE under pipefail) before the sweep.
  evict-many =
    evict "many" 2000 1000 ''
      mkdir data/d; for i in $(seq 3000); do echo > "data/d/blob-with-a-longish-name-$i"; done
      touch -d "10 days ago" data/d/blob-with-a-longish-name-3000
    '' ''
      grep -q '^mbx-cache --sweep-metadata-older-than-days ' calls || fail "no sweep after evicting a large listing"
    '';

  # A directory the cache account can't read (DSM's @eaDir indexing) doesn't
  # stop eviction.
  evict-unreadable-dir =
    evict "unreadable-dir" 350 200 ''
      blob a "30 days ago"; blob b "20 days ago"; blob c "10 days ago"; blob d "1 hour ago"
      mkdir -p data/@eaDir/x && chmod 000 data/@eaDir
    '' ''
      chmod 755 data/@eaDir
      [ ! -e data/a ] || fail "nothing evicted"
      grep -q '^mbx-cache --sweep-metadata-older-than-days ' calls || fail "no sweep"
    '';

  # A declared volume that differs from where the share lives is an error,
  # not a set: DSM would move the share's data.
  share-volume-not-moved = scenario "share-volume-not-moved" ''
    mkdir -p $ROOT/shares
    echo '{"name": "mbx-cache", "vol_path": "/volume1", "desc": "mbx build cache", "hidden": true, "enable_recycle_bin": false, "quota_value": 500000}' > $ROOT/shares/mbx-cache.json
    if run ${genShare 500000}; then fail "volume mismatch accepted"; fi
    ! called "synowebapi SYNO.Core.Share set mbx-cache" || fail "share set (would move it)"
    jq -e '.vol_path == "/volume1"' $ROOT/shares/mbx-cache.json >/dev/null || fail "moved"
  '';

  nas-units-guarded = check "nas-units-guarded" ''
    u=${hostGeneration}/units
    for n in nix-postgresql mbx-cache mbx-cache-evict; do
      grep -qx 'ConditionPathIsMountPoint=/volume2' $u/$n.service || fail "$n runs without /volume2 mounted"
    done
    pre=$(sed -n 's/^ExecStartPre=//p' $u/nix-postgresql.service)
    ! grep -q 'install -d' $pre || grep -q '/volume2/@appdata ]' $pre || fail "pre-start creates the data dir's parents unchecked"
    for n in nix-postgresql mbx-cache mbx-cache-evict mbx-cache-serve nix-store-gc host-watch-nutmeg; do
      grep -qx 'OnFailure=notify-failure@%n.service' $u/$n.service || fail "$n has no failure alert"
    done
  '';

  # DSM grants administrators rw on a new share; "none" takes that away.
  share-group-revoked = scenario "share-group-revoked" ''
    mkdir -p $ROOT/shares
    echo '{"name": "mbx-cache", "vol_path": "/volume2", "desc": "mbx build cache", "hidden": true, "enable_recycle_bin": false, "quota_value": 500000}' > $ROOT/shares/mbx-cache.json
    echo '[{"name": "administrators", "is_readonly": false, "is_writable": true, "is_deny": false, "is_custom": false}]' > $ROOT/shares/mbx-cache.local_group.json
    run ${genShareGroups}
    jq -e '.[] | select(.name == "administrators") | (.is_writable or .is_readonly or .is_deny) | not' $ROOT/shares/mbx-cache.local_group.json >/dev/null ||
      fail "group grant: $(cat $ROOT/shares/mbx-cache.local_group.json)"
    run ${genShareGroups}
    ! called_matching 'Share.Permission set' || fail "group grant re-set on an unchanged run"
  '';

  # The host's mbx-cache share takes administrators' default access away.
  mbx-share-groups = check "mbx-share-groups" ''
    jq -e '."mbx-cache".groups == {"administrators": "none"}' ${hostGeneration}/dsm-shares.json >/dev/null || fail "groups: $(cat ${hostGeneration}/dsm-shares.json)"
  '';

  # PostgreSQL's post-start waits about as long as the unit's start timeout,
  # and fails plainly if the server never becomes ready.
  pg-ready-wait = check "pg-ready-wait" ''
    post=$(sed -n 's/^ExecStartPost=//p' ${hostGeneration}/units/nix-postgresql.service)
    grep -q 'seq 220' $post || fail "readiness wait too short: $(grep seq $post)"
    grep -q 'never became ready' $post || fail "no explicit failure"
  '';

  # The watcher checks nutmeg's LAN address before blaming nutmeg for what may
  # be the NAS's own tailnet link; cleanup runs every 6 hours.
  watch-lan-fallback = check "watch-lan-fallback" ''
    probe=$(sed -n 's/^ExecStart=//p' ${hostGeneration}/units/host-watch-nutmeg.service)
    grep -q '2600:2b00:9b16:6d01::228' $probe || fail "no LAN fallback"
    grep -qx 'OnCalendar=00/6:30' ${hostGeneration}/units/mbx-cache-evict.timer || fail "cleanup cadence: $(grep OnCalendar ${hostGeneration}/units/mbx-cache-evict.timer)"
  '';

  tailscale-migrate-copies =
    tsMigrate "copies" ''
      echo state > old/tailscaled.state; mkdir old/certs; echo cert > old/certs/a.crt
      echo 123 > old/tailscaled.pid; : > old/tailscaled.sock; echo log > old/tailscaled.stdout.log
    '' ''
      [ "$(cat new/tailscaled.state)" = state ] && [ "$(cat new/certs/a.crt)" = cert ] || fail "state not copied: $(find new)"
      [ ! -e new/tailscaled.pid ] && [ ! -e new/tailscaled.sock ] && [ ! -e new/tailscaled.stdout.log ] || fail "runtime files copied: $(find new)"
      grep -q "^chown -R 0:0 $PWD/new" calls || fail "not chowned to root: $(cat calls)"
      [ "$(stat -c %a new)" = 700 ] || fail "dir mode $(stat -c %a new)"
    '';

  # Only ever once: the nix daemon's own state is never overwritten.
  tailscale-migrate-keeps-existing =
    tsMigrate "keeps-existing" ''
      echo old-state > old/tailscaled.state
      mkdir new; echo new-state > new/tailscaled.state
    '' ''
      [ "$(cat new/tailscaled.state)" = new-state ] || fail "existing state overwritten"
      [ ! -s calls ] || fail "touched an existing state dir"
    '';

  tailscale-migrate-nothing = tsMigrate "nothing" "" ''
    [ ! -e new/tailscaled.state ] || fail "invented a state"
  '';

  tailscale-units = check "tailscale-units" ''
    g=${hostGeneration}
    u=$g/units/nix-tailscaled.service
    [ -e $g/wants/multi-user.target/nix-tailscaled.service ] || fail "not started at boot"
    grep -qx 'Conflicts=pkgctl-Tailscale.service' $u || fail "can run alongside the Synology package"
    grep -qx 'After=pkgctl-Tailscale.service network-online.target' $u || fail "not ordered after the package stops"
    grep -q -- '--state=/volume2/@appdata/nix-tailscale/tailscaled.state' $u || fail "state path"
    grep -q -- '--port=41641' $u || fail "port"
    grep -q 'TS_DEBUG_FIREWALL_MODE=iptables' $u || fail "firewall mode"
    grep -q 'accept-dns=false' $(sed -n 's/^ExecStartPost=//p' $u) || fail "MagicDNS would rewrite DSM's resolv.conf"
    # On a Synology the CLI looks for the package's socket unless told otherwise.
    for s in $(sed -n 's/^ExecStartPost=//p' $u) $(sed -n 's/^ExecStart=//p' $g/units/mbx-cache-serve.service) $g/default-profile/bin/tailscale; do
      # Each tailscale it calls either gets --socket on that line or is a
      # wrapper that passes it.
      for t in $(grep -o '/nix/store/[^/ ]*/bin/tailscale' $s | sort -u); do
        grep -qF -- "$t --socket=/run/tailscale/tailscaled.sock" $s ||
          grep -q -- '--socket=/run/tailscale/tailscaled.sock' "$t" ||
          fail "$s calls $t without the socket"
      done
    done
    grep -q 'tailscale-migrate' $(sed -n 's/^ExecStartPre=//p' $u | head -1) || fail "no state migration"
    jq -e '.tailscale.enable == false' $g/dsm-services.json >/dev/null || fail "Synology package not stopped"
    jq -e '."tailscale update".enable == false and ."tailscale tunnel".enable == false' $g/dsm-tasks.json >/dev/null || fail "package tasks still enabled"
    serve=$(sed -n 's/^ExecStart=//p' $g/units/mbx-cache-serve.service)
    ! grep -q '/var/packages/Tailscale' $serve || fail "serve still uses the Synology CLI"
    # activate starts units one at a time, so After= alone doesn't hold at boot.
    grep -qx 'Wants=nix-tailscaled.service' $g/units/mbx-cache-serve.service || fail "serve doesn't pull in nix-tailscaled"
    [ -x $g/default-profile/bin/tailscale ] || fail "no tailscale CLI on root's PATH"
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
