# shellcheck disable=SC2016 # jq filters reference $vars passed with --arg
# Apply a potato-bunny system generation. Runs as root on every deploy and at
# every boot (from the DSM Task Scheduler boot-up task), so every step is
# idempotent: a second run with nothing changed starts, restarts and creates
# nothing.
#
# Usage: activate --generation <store path> [--root <dir>] [--boot] [--dry-run]
#
# --boot (from the boot task) skips the DSM package and settings steps.
# --dry-run prints the DSM changes a real run would make ("would: ..."), or
# "no DSM changes", and changes nothing at all.
#
# --root prefixes every filesystem path (the tests use a scratch root). DSM's
# tools come from SYSTEMCTL, SYNOUSER, SYNOGROUP, SYNOWEBAPI, SYNOPKG and
# NIX_ENV, and the daemon health probe from DAEMON_PROBE, so the tests can
# stub them.
#
# Ownership rules:
# - /etc: only declared files under /etc/nix are written or removed.
# - /etc/systemd/system: a path is ours only if it is a symlink into
#   /nix/store. Declaring a unit whose name DSM already uses is refused, except
#   the installer's nix-daemon units, which this layer takes over. Nothing else
#   is ever replaced or removed.
# - nix-daemon: restarted first, verified by talking to its socket, and rolled
#   back (unit link and /etc/nix) if it doesn't answer. Never removed.
# - Accounts: only through synouser/synogroup; users and members are only ever
#   added. passwd, group and shadow are never opened.
# - DSM boot-up/shutdown tasks: created and updated through DSM's own
#   EventScheduler API (what its UI uses); never deleted.
# - DSM packages, feeds, settings and scheduled tasks (dsm.sh): only what is
#   declared; nothing is ever uninstalled or deleted. A failure there is
#   reported and the rest still applies; activate then exits non-zero.

GEN=""
ROOT=""
BOOT=false
DRY_RUN=false
while [ $# -gt 0 ]; do
  case "$1" in
    --generation) GEN=$2; shift 2 ;;
    --root) ROOT=$2; shift 2 ;;
    --boot) BOOT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "activate: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$GEN" ] || { echo "activate: --generation is required" >&2; exit 2; }

SYSTEMCTL=${SYSTEMCTL:-/usr/bin/systemctl}
SYNOUSER=${SYNOUSER:-/usr/syno/sbin/synouser}
SYNOGROUP=${SYNOGROUP:-/usr/syno/sbin/synogroup}
SYNOWEBAPI=${SYNOWEBAPI:-/usr/syno/bin/synowebapi}
SYNOPKG=${SYNOPKG:-/usr/syno/bin/synopkg}
NIX_ENV=${NIX_ENV:-nix-env}
DAEMON_PROBE=${DAEMON_PROBE:-}
DAEMON_TIMEOUT=${ACTIVATE_DAEMON_TIMEOUT:-10}
DAEMON_SETTLE=${ACTIVATE_DAEMON_SETTLE:-2}

SYSTEMD_DIR=$ROOT/etc/systemd/system
DSM_UNIT_DIR=/usr/lib/systemd/system
STATE_DIR=$ROOT/volume1/@appdata/nix-system
STATE=$STATE_DIR/state.json
INSTALLER_UNITS=/nix/var/nix/profiles/default/lib/systemd/system/
# Unit names DSM never ships but the nix installer links; ours to take over.
TAKEOVER=" nix-daemon.service nix-daemon.socket "

log() { echo "activate: $*" >&2; }
die() { log "$*"; exit 1; }

mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/lock"
flock 9

# A dry run prints the DSM changes a real run would make, and changes nothing.
if $DRY_RUN; then
  DSM_PLANNED=false
  dsm_event_tasks
  dsm_apply
  $DSM_PLANNED || echo "no DSM changes"
  if [ ${#DSM_FAILURES[@]} -gt 0 ]; then exit 1; fi
  exit 0
fi

# ---------------------------------------------------------------- state

EMPTY_STATE='{"generation": null, "etc": [], "units": {}, "wants": []}'
OLD_STATE=$EMPTY_STATE
if [ -s "$STATE" ]; then
  if jq -e 'type == "object"' "$STATE" >/dev/null 2>&1; then
    OLD_STATE=$(jq '{generation: .generation, etc: (.etc // []), units: (.units // {}), wants: (.wants // [])}' "$STATE")
  else
    log "warning: $STATE is not valid JSON; treating it as empty"
  fi
fi
OLD_GEN=$(jq -r '.generation // empty' <<<"$OLD_STATE")
[ -n "$OLD_GEN" ] && [ ! -d "$OLD_GEN" ] && OLD_GEN=""

# ---------------------------------------------------------------- names

# /etc paths: under nix/, no empty, "." or ".." components.
valid_etc() {
  case "$1" in nix/?*) ;; *) return 1 ;; esac
  case "/$1/" in *//* | */./* | */../*) return 1 ;; esac
}
# Unit names: "name.type" or one drop-in level "name.type.d/file.conf".
valid_unit() {
  [[ $1 =~ ^[A-Za-z0-9@_.:-]+(\.d/[A-Za-z0-9@_.:-]+)?$ ]] || return 1
  case "$1" in . | .. | *..*) return 1 ;; esac
}
valid_want() {
  [[ $1 =~ ^[A-Za-z0-9@_.:-]+/[A-Za-z0-9@_.:-]+$ ]] || return 1
  case "$1" in *..*) return 1 ;; esac
}

list_files() { # list_files <dir>: relative paths of regular files, sorted
  [ -d "$1" ] || return 0
  (cd "$1" && find . -type f | sed 's|^\./||' | sort)
}

mapfile -t declared_etc < <(list_files "$GEN/etc")
mapfile -t declared_units < <(list_files "$GEN/units")
mapfile -t declared_wants < <(list_files "$GEN/wants")

for rel in "${declared_etc[@]}"; do valid_etc "$rel" || die "refusing /etc/$rel: only /etc/nix is managed"; done
for u in "${declared_units[@]}"; do valid_unit "$u" || die "refusing unit name $u"; done
for w in "${declared_wants[@]}"; do valid_want "$w" || die "refusing wants entry $w"; done

declared() {
  local u
  for u in "${declared_units[@]}"; do [ "$u" = "$1" ] && return 0; done
  return 1
}

# A path in /etc/systemd/system is ours only if it is a symlink into the store.
ours() { [ -L "$1" ] && case "$(readlink "$1")" in /nix/store/*) true ;; *) false ;; esac; }
installer_link() { [ -L "$1" ] && case "$(readlink "$1")" in "$INSTALLER_UNITS"*) true ;; *) false ;; esac; }

# The unit a drop-in belongs to ("user@1027.service.d/x.conf" -> "user@1027.service").
owner_of() { case "$1" in */*) echo "${1%%.d/*}" ;; *) echo "$1" ;; esac; }

# Where <target>.wants/<name> should point.
want_dest() {
  if declared "$1"; then
    echo "/etc/systemd/system/$1"
  else
    # A unit DSM ships, typically a template instance: user@1027.service -> user@.service.
    echo "$DSM_UNIT_DIR/$(sed -E 's/@[^.]*\./@./' <<<"$1")"
  fi
}

# Refuse names DSM already uses, before changing anything.
for u in "${declared_units[@]}"; do
  case "$u" in */*) continue ;; esac
  case "$TAKEOVER" in *" $u "*) continue ;; esac
  path=$SYSTEMD_DIR/$u
  if [ -e "$path" ] || [ -L "$path" ]; then
    ours "$path" || die "refusing to replace DSM's $path"
  fi
  [ ! -e "$ROOT$DSM_UNIT_DIR/$u" ] || die "refusing to shadow DSM's $DSM_UNIT_DIR/$u"
done

unit_hash() { sha256sum "$GEN/units/$1" | cut -d' ' -f1; }
is_exempt() { grep -qxF "$1" "$GEN/restart-exempt" 2>/dev/null; }

# ---------------------------------------------------------------- pending state

# Root the generation before anything points into it.
mkdir -p "$ROOT/nix/var/nix/gcroots"
ln -sfn "$GEN" "$ROOT/nix/var/nix/gcroots/potato-bunny-pending"

# If this run dies part-way, the next one must still know about everything
# either generation installed, so record the union now.
write_state() { # write_state <json>
  local tmp
  tmp=$(mktemp "$STATE.XXXXXX")
  cat >"$tmp" <<<"$1"
  mv -f "$tmp" "$STATE"
}
new_lists=$(jq -n --args '$ARGS.positional' "${declared_etc[@]}")
new_wants=$(jq -n --args '$ARGS.positional' "${declared_wants[@]}")
new_units=$(jq -n --args '$ARGS.positional | map({(.): "pending"}) | add // {}' "${declared_units[@]}")
write_state "$(jq --argjson e "$new_lists" --argjson w "$new_wants" --argjson u "$new_units" \
  '.etc = (.etc + $e | unique) | .wants = (.wants + $w | unique) | .units = ($u + .units)' <<<"$OLD_STATE")"

PREV_DAEMON_LINK=$(readlink "$SYSTEMD_DIR/nix-daemon.service" 2>/dev/null || true)

# ---------------------------------------------------------------- /etc files

etc_changed=false
for rel in "${declared_etc[@]}"; do
  dest=$ROOT/etc/$rel
  if ! cmp -s "$GEN/etc/$rel" "$dest" 2>/dev/null; then
    log "writing /etc/$rel"
    mkdir -p "$(dirname "$dest")"
    tmp=$(mktemp "$dest.XXXXXX")
    cat "$GEN/etc/$rel" >"$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$dest"
    etc_changed=true
  fi
done

while IFS= read -r rel; do
  valid_etc "$rel" || { log "warning: ignoring /etc/$rel from state"; continue; }
  if [ ! -e "$GEN/etc/$rel" ] && [ -f "$ROOT/etc/$rel" ]; then
    log "removing /etc/$rel"
    rm -f "$ROOT/etc/$rel"
    etc_changed=true
  fi
done < <(jq -r '.etc[]' <<<"$OLD_STATE")

# ---------------------------------------------------------------- units

# Units and wants links the previous generation installed and this one dropped.
while IFS= read -r u; do
  valid_unit "$u" || { log "warning: ignoring unit $u from state"; continue; }
  declared "$u" && continue
  if [ "$u" = nix-daemon.service ]; then
    log "warning: generation has no nix-daemon.service; keeping the current one"
    continue
  fi
  path=$SYSTEMD_DIR/$u
  ours "$path" || continue
  case "$u" in
    */*) ;;
    *) log "stopping $u"; "$SYSTEMCTL" stop "$u" || log "warning: stopping $u failed" ;;
  esac
  rm -f "$path"
  case "$u" in */*) rmdir "$(dirname "$path")" 2>/dev/null || true ;; esac
done < <(jq -r '.units | keys[]' <<<"$OLD_STATE")

while IFS= read -r w; do
  valid_want "$w" || { log "warning: ignoring wants entry $w from state"; continue; }
  [ -e "$GEN/wants/$w" ] && continue
  target=${w%%/*}
  name=${w#*/}
  path=$SYSTEMD_DIR/$target.wants/$name
  # Only a link pointing exactly where we would have pointed it is ours.
  # (Our own units are judged by the state, since their links are already gone.)
  if [ -L "$path" ] && { [ "$(readlink "$path")" = "/etc/systemd/system/$name" ] && jq -e --arg n "$name" '.units | has($n)' <<<"$OLD_STATE" >/dev/null ||
    [ "$(readlink "$path")" = "$DSM_UNIT_DIR/$(sed -E 's/@[^.]*\./@./' <<<"$name")" ]; }; then
    rm -f "$path"
    rmdir "$SYSTEMD_DIR/$target.wants" 2>/dev/null || true
  fi
done < <(jq -r '.wants[]' <<<"$OLD_STATE")

# The installer's socket unit would keep socket-activating whatever
# nix-daemon.service is; the daemon here runs on its own.
if declared nix-daemon.service && installer_link "$SYSTEMD_DIR/nix-daemon.socket"; then
  log "removing the installer's nix-daemon.socket"
  "$SYSTEMCTL" stop nix-daemon.socket || log "warning: stopping nix-daemon.socket failed"
  rm -f "$SYSTEMD_DIR/nix-daemon.socket"
  installer_link "$SYSTEMD_DIR/sockets.target.wants/nix-daemon.socket" &&
    rm -f "$SYSTEMD_DIR/sockets.target.wants/nix-daemon.socket"
fi

for u in "${declared_units[@]}"; do
  path=$SYSTEMD_DIR/$u
  mkdir -p "$(dirname "$path")"
  [ "$(readlink "$path" 2>/dev/null)" = "$GEN/units/$u" ] || ln -sfn "$GEN/units/$u" "$path"
done

for w in "${declared_wants[@]}"; do
  target=${w%%/*}
  name=${w#*/}
  dest=$(want_dest "$name")
  path=$SYSTEMD_DIR/$target.wants/$name
  if [ -L "$path" ] && [ "$(readlink "$path")" != "$dest" ]; then
    log "warning: $path points elsewhere ($(readlink "$path")); leaving it"
    continue
  fi
  mkdir -p "$SYSTEMD_DIR/$target.wants"
  [ -L "$path" ] || ln -s "$dest" "$path"
done

"$SYSTEMCTL" daemon-reload

# A unit counts as changed if its contents differ from the previous
# generation's, or if it is new to the state but already running under that
# name (the first activation over the installer's daemon, a new drop-in for a
# running DSM unit).
changed=()
for u in "${declared_units[@]}"; do
  prev=$(jq -r --arg u "$u" '.units[$u] // empty' <<<"$OLD_STATE")
  if [ -n "$prev" ]; then
    [ "$prev" = "$(unit_hash "$u")" ] || changed+=("$u")
  elif "$SYSTEMCTL" is-active --quiet "$(owner_of "$u")"; then
    changed+=("$u")
  fi
done

# ---------------------------------------------------------------- accounts

# Before any unit starts, so a service's User= exists when it does.

members_of() {
  "$SYNOGROUP" --get "$1" 2>/dev/null | sed -nE 's/^[0-9]+:\[(.*)\]$/\1/p'
}
add_member() { # add_member <group> <user>: only ever adds
  if ! members_of "$1" | grep -qxF "$2"; then
    log "adding $2 to $1"
    "$SYNOGROUP" --memberadd "$1" "$2" >/dev/null
  fi
}

# Groups first, so users' extraGroups can name groups this generation creates.
while IFS= read -r group; do
  [ -n "$group" ] || continue
  if ! "$SYNOGROUP" --get "$group" >/dev/null 2>&1; then
    log "creating group $group"
    "$SYNOGROUP" --add "$group" >/dev/null
  fi
  while IFS= read -r member; do
    [ -n "$member" ] && add_member "$group" "$member"
  done < <(jq -r --arg g "$group" '.groups[$g][]' "$GEN/users.json")
done < <(jq -r '.groups | keys[]' "$GEN/users.json")

while IFS= read -r user; do
  [ -n "$user" ] || continue
  if ! "$SYNOUSER" --get "$user" >/dev/null 2>&1; then
    log "creating user $user"
    desc=$(jq -r --arg u "$user" '.users[$u].description' "$GEN/users.json")
    # The account only runs services; nobody logs in with this password. The
    # suffix satisfies DSM's optional mixed-class password rules.
    pw="$(head -c 24 /dev/urandom | base64 | tr -d '\n')Aa1!"
    "$SYNOUSER" --add "$user" "$pw" "$desc" 0 "" 0 >/dev/null
  fi
  while IFS= read -r group; do
    [ -n "$group" ] && add_member "$group" "$user"
  done < <(jq -r --arg u "$user" '.users[$u].extraGroups[]' "$GEN/users.json")
done < <(jq -r '.users | keys[]' "$GEN/users.json")

# ---------------------------------------------------------------- DSM tasks

dsm_event_tasks

# ---------------------------------------------------------------- nix-daemon

probe_daemon() {
  if [ -n "$DAEMON_PROBE" ]; then
    "$DAEMON_PROBE"
  else
    "$GEN/default-profile/bin/nix-store" --store daemon --query --hash "$GEN" >/dev/null 2>&1
  fi
}

# The daemon must be active and answer on its socket, and still answer after
# settling (a crash-looping simple service looks active right after fork).
daemon_healthy() {
  local i
  for ((i = 0; i < DAEMON_TIMEOUT * 2; i++)); do
    if "$SYSTEMCTL" is-active --quiet nix-daemon.service && probe_daemon; then
      sleep "$DAEMON_SETTLE"
      "$SYSTEMCTL" is-active --quiet nix-daemon.service && probe_daemon && return 0
    fi
    sleep 0.5
  done
  return 1
}

rollback_daemon() {
  log "nix-daemon is not answering; rolling back"
  if [ -n "$OLD_GEN" ]; then
    for rel in "${declared_etc[@]}"; do
      if [ -f "$OLD_GEN/etc/$rel" ]; then
        cat "$OLD_GEN/etc/$rel" >"$ROOT/etc/$rel"
      else
        rm -f "$ROOT/etc/$rel"
      fi
    done
  fi
  if [ -n "$PREV_DAEMON_LINK" ]; then
    ln -sfn "$PREV_DAEMON_LINK" "$SYSTEMD_DIR/nix-daemon.service"
  fi
  "$SYSTEMCTL" daemon-reload
  "$SYSTEMCTL" restart nix-daemon.service || true
  if daemon_healthy; then
    log "previous nix-daemon restored"
  else
    log "previous nix-daemon is not answering either"
  fi
}

daemon_failed=false
if declared nix-daemon.service; then
  daemon_changed=$etc_changed
  for u in "${changed[@]}"; do
    [ "$(owner_of "$u")" = nix-daemon.service ] && daemon_changed=true
  done
  if $daemon_changed; then
    log "restarting nix-daemon.service"
    "$SYSTEMCTL" restart nix-daemon.service || true
  elif ! "$SYSTEMCTL" is-active --quiet nix-daemon.service; then
    log "starting nix-daemon.service"
    "$SYSTEMCTL" start nix-daemon.service || true
  fi
  if ! daemon_healthy; then
    if $daemon_changed; then
      rollback_daemon
      die "nix-daemon is not healthy; state not advanced"
    fi
    # Nothing to roll back to (typically at boot): bring up everything else,
    # which doesn't need the daemon, then fail without advancing anything.
    log "nix-daemon is not healthy; starting the other units anyway"
    daemon_failed=true
  fi
fi

# ---------------------------------------------------------------- other units

restart_set=()
for u in "${changed[@]}"; do
  owner=$(owner_of "$u")
  [ "$owner" = nix-daemon.service ] && continue
  is_exempt "$u" && continue
  case " ${restart_set[*]} " in *" $owner "*) ;; *) restart_set+=("$owner") ;; esac
done

for owner in "${restart_set[@]}"; do
  if "$SYSTEMCTL" is-active --quiet "$owner"; then
    log "restarting $owner"
    "$SYSTEMCTL" restart "$owner" || log "warning: restarting $owner failed"
  fi
done

for w in "${declared_wants[@]}"; do
  name=${w#*/}
  [ "$name" = nix-daemon.service ] && continue
  if ! "$SYSTEMCTL" is-active --quiet "$name"; then
    log "starting $name"
    "$SYSTEMCTL" start "$name" || log "warning: $name failed to start"
  fi
done

# ---------------------------------------------------------------- DSM packages and settings

# At deploy only: DSM keeps all of this across reboots itself, and at boot it
# is still starting its own packages, so synopkg would race it.
$BOOT || dsm_apply

# ---------------------------------------------------------------- profiles

$daemon_failed && die "nix-daemon is not healthy; profiles and state not advanced"

switch_profile() { # switch_profile <profile> <target>
  if [ "$(readlink -f "$1" 2>/dev/null)" != "$(readlink -f "$2")" ]; then
    log "switching $1"
    # Resolve first: nix-env --set takes the store path *containing* its
    # argument, so $GEN/default-profile would become $GEN itself.
    "$NIX_ENV" -p "$1" --set "$(readlink -f "$2")"
  fi
}
switch_profile "$ROOT/nix/var/nix/profiles/potato-bunny" "$GEN"
if [ -e "$GEN/default-profile" ]; then
  switch_profile "$ROOT/nix/var/nix/profiles/default" "$GEN/default-profile"
fi

# ---------------------------------------------------------------- state

units_json=$(
  for u in "${declared_units[@]}"; do
    jq -n --arg u "$u" --arg h "$(unit_hash "$u")" '{($u): $h}'
  done | jq -s 'add // {}'
)
write_state "$(jq -n --arg gen "$GEN" --argjson e "$new_lists" --argjson w "$new_wants" --argjson u "$units_json" \
  '{generation: $gen, etc: $e, units: $u, wants: $w}')"
if [ ${#DSM_FAILURES[@]} -gt 0 ]; then
  die "done, except: $(printf "%s; " "${DSM_FAILURES[@]}")"
fi
log "done"
