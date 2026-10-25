# shellcheck disable=SC2016 # jq filters reference $vars passed with --arg
# Apply a potato-bunny system generation. Runs as root on every deploy and at
# every boot (from the DSM Task Scheduler boot-up task), so every step is
# idempotent: a second run with nothing changed starts, restarts and creates
# nothing.
#
# Usage: activate --generation <store path> [--root <dir>]
#
# --root prefixes every filesystem path (the tests use a scratch root). DSM's
# tools are taken from SYSTEMCTL, SYNOUSER, SYNOGROUP and NIX_ENV so the tests
# can stub them; NIX_ENV=true skips the profile switches.
#
# Ownership rules:
# - /etc: only the files this layer declared are written or removed.
# - /etc/systemd/system: only symlinks into /nix/store are ever removed, and
#   only when the previous state lists them. DSM's own units are never touched.
# - Accounts: only through synouser/synogroup; never deleted. passwd, group
#   and shadow are never opened.

GEN=""
ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --generation) GEN=$2; shift 2 ;;
    --root) ROOT=$2; shift 2 ;;
    *) echo "activate: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$GEN" ] || { echo "activate: --generation is required" >&2; exit 2; }

SYSTEMCTL=${SYSTEMCTL:-/usr/bin/systemctl}
SYNOUSER=${SYNOUSER:-/usr/syno/sbin/synouser}
SYNOGROUP=${SYNOGROUP:-/usr/syno/sbin/synogroup}
NIX_ENV=${NIX_ENV:-nix-env}
DAEMON_TIMEOUT=${ACTIVATE_DAEMON_TIMEOUT:-10}

SYSTEMD_DIR=$ROOT/etc/systemd/system
STATE_DIR=$ROOT/volume1/@appdata/nix-system
STATE=$STATE_DIR/state.json
DSM_UNIT_DIR=/usr/lib/systemd/system

log() { echo "activate: $*" >&2; }

if [ -f "$STATE" ]; then
  OLD_STATE=$(cat "$STATE")
else
  OLD_STATE='{"generation": null, "etc": [], "units": {}, "wants": []}'
fi
old() { jq -r "$1" <<<"$OLD_STATE"; }
OLD_GEN=$(old '.generation // empty')

# ---------------------------------------------------------------- /etc files

declared_etc=()
if [ -d "$GEN/etc" ]; then
  while IFS= read -r -d '' f; do
    declared_etc+=("${f#"$GEN/etc/"}")
  done < <(find "$GEN/etc" -type f -print0 | sort -z)
fi

for rel in "${declared_etc[@]}"; do
  dest=$ROOT/etc/$rel
  if ! cmp -s "$GEN/etc/$rel" "$dest" 2>/dev/null; then
    log "writing /etc/$rel"
    mkdir -p "$(dirname "$dest")"
    tmp=$(mktemp "$dest.XXXXXX")
    cat "$GEN/etc/$rel" >"$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$dest"
  fi
done

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  if [ ! -e "$GEN/etc/$rel" ] && [ -f "$ROOT/etc/$rel" ]; then
    log "removing /etc/$rel"
    rm -f "$ROOT/etc/$rel"
  fi
done < <(old '.etc[]')

# ---------------------------------------------------------------- units

# Unit names relative to units/, drop-ins included ("user@1027.service.d/x.conf").
declared_units=()
if [ -d "$GEN/units" ]; then
  while IFS= read -r -d '' f; do
    declared_units+=("${f#"$GEN/units/"}")
  done < <(find "$GEN/units" -type f -print0 | sort -z)
fi

declared_wants=()
if [ -d "$GEN/wants" ]; then
  while IFS= read -r -d '' f; do
    declared_wants+=("${f#"$GEN/wants/"}")
  done < <(find "$GEN/wants" -type f -print0 | sort -z)
fi

unit_hash() { sha256sum "$GEN/units/$1" | cut -d' ' -f1; }

# A path in /etc/systemd/system is ours to remove only if it is a symlink into the store.
ours() { [ -L "$1" ] && case "$(readlink "$1")" in /nix/store/*) true ;; *) false ;; esac; }

# The unit a drop-in belongs to ("user@1027.service.d/x.conf" -> "user@1027.service").
owner_of() { case "$1" in */*) echo "${1%%.d/*}" ;; *) echo "$1" ;; esac; }

is_exempt() { grep -qxF "$1" "$GEN/restart-exempt" 2>/dev/null; }

declared() {
  local u
  for u in "${declared_units[@]}"; do [ "$u" = "$1" ] && return 0; done
  return 1
}

# Remove units and wants links the previous generation installed and this one dropped.
stopped=()
while IFS= read -r u; do
  [ -n "$u" ] || continue
  declared "$u" && continue
  path=$SYSTEMD_DIR/$u
  ours "$path" || continue
  case "$u" in
    */*) ;;
    *) log "stopping $u"; "$SYSTEMCTL" stop "$u" || true; stopped+=("$u") ;;
  esac
  rm -f "$path"
  case "$u" in */*) rmdir "$(dirname "$path")" 2>/dev/null || true ;; esac
done < <(old '.units | keys[]')

while IFS= read -r w; do
  [ -n "$w" ] || continue
  if [ ! -e "$GEN/wants/$w" ]; then
    target=${w%%/*}
    name=${w#*/}
    path=$SYSTEMD_DIR/$target.wants/$name
    if [ -L "$path" ]; then
      rm -f "$path"
      rmdir "$SYSTEMD_DIR/$target.wants" 2>/dev/null || true
    fi
  fi
done < <(old '.wants[]')

# Link declared units and wants.
for u in "${declared_units[@]}"; do
  path=$SYSTEMD_DIR/$u
  mkdir -p "$(dirname "$path")"
  if [ "$(readlink "$path" 2>/dev/null)" != "$GEN/units/$u" ]; then
    ln -sfn "$GEN/units/$u" "$path"
  fi
done

for w in "${declared_wants[@]}"; do
  target=${w%%/*}
  name=${w#*/}
  if declared "$name"; then
    dest=/etc/systemd/system/$name
  else
    # A unit DSM ships, typically a template instance: user@1027.service -> user@.service.
    dest=$DSM_UNIT_DIR/$(sed -E 's/@[^.]*\./@./' <<<"$name")
  fi
  mkdir -p "$SYSTEMD_DIR/$target.wants"
  if [ "$(readlink "$SYSTEMD_DIR/$target.wants/$name" 2>/dev/null)" != "$dest" ]; then
    ln -sfn "$dest" "$SYSTEMD_DIR/$target.wants/$name"
  fi
done

"$SYSTEMCTL" daemon-reload

# Restart changed units, start wanted ones that aren't running. nix-daemon is
# handled last, separately, so a bad daemon can be rolled back.
changed=()
for u in "${declared_units[@]}"; do
  prev=$(jq -r --arg u "$u" '.units[$u] // empty' <<<"$OLD_STATE")
  # A unit new in this generation is started below, not restarted.
  [ -n "$prev" ] || continue
  [ "$prev" = "$(unit_hash "$u")" ] || changed+=("$u")
done

restart_set=()
for u in "${changed[@]}"; do
  is_exempt "$u" && continue
  owner=$(owner_of "$u")
  [ "$owner" = nix-daemon.service ] && continue
  case " ${restart_set[*]} " in *" $owner "*) ;; *) restart_set+=("$owner") ;; esac
done

for owner in "${restart_set[@]}"; do
  if "$SYSTEMCTL" is-active --quiet "$owner"; then
    log "restarting $owner"
    "$SYSTEMCTL" restart "$owner"
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

# ---------------------------------------------------------------- nix-daemon

daemon_changed=false
for u in "${changed[@]}"; do [ "$u" = nix-daemon.service ] && daemon_changed=true; done

wait_daemon() {
  local i
  for ((i = 0; i < DAEMON_TIMEOUT * 2; i++)); do
    "$SYSTEMCTL" is-active --quiet nix-daemon.service && return 0
    sleep 0.5
  done
  return 1
}

if declared nix-daemon.service; then
  if $daemon_changed; then
    log "restarting nix-daemon.service"
    "$SYSTEMCTL" restart nix-daemon.service || true
  elif ! "$SYSTEMCTL" is-active --quiet nix-daemon.service; then
    log "starting nix-daemon.service"
    "$SYSTEMCTL" start nix-daemon.service || true
  fi
  if ! wait_daemon; then
    if $daemon_changed && [ -n "$OLD_GEN" ] && [ -f "$OLD_GEN/units/nix-daemon.service" ]; then
      log "nix-daemon failed to start; rolling back to $OLD_GEN"
      ln -sfn "$OLD_GEN/units/nix-daemon.service" "$SYSTEMD_DIR/nix-daemon.service"
      "$SYSTEMCTL" daemon-reload
      "$SYSTEMCTL" restart nix-daemon.service || true
    fi
    log "nix-daemon is not running; state not updated"
    exit 1
  fi
fi

# ---------------------------------------------------------------- accounts

members_of() {
  "$SYNOGROUP" --get "$1" 2>/dev/null | sed -nE 's/^[0-9]+:\[(.*)\]$/\1/p'
}

while IFS= read -r user; do
  [ -n "$user" ] || continue
  if ! "$SYNOUSER" --get "$user" >/dev/null 2>&1; then
    log "creating user $user"
    desc=$(jq -r --arg u "$user" '.users[$u].description' "$GEN/users.json")
    # The account is for running services; nobody logs in with this password.
    pw=$(head -c 24 /dev/urandom | base64 | tr -d '\n')
    "$SYNOUSER" --add "$user" "$pw" "$desc" 0 "" 0 >/dev/null
  fi
  while IFS= read -r group; do
    [ -n "$group" ] || continue
    if ! members_of "$group" | grep -qxF "$user"; then
      log "adding $user to $group"
      "$SYNOGROUP" --memberadd "$group" "$user" >/dev/null
    fi
  done < <(jq -r --arg u "$user" '.users[$u].extraGroups[]' "$GEN/users.json")
done < <(jq -r '.users | keys[]' "$GEN/users.json")

while IFS= read -r group; do
  [ -n "$group" ] || continue
  if ! "$SYNOGROUP" --get "$group" >/dev/null 2>&1; then
    log "creating group $group"
    "$SYNOGROUP" --add "$group" >/dev/null
  fi
  want=$(jq -r --arg g "$group" '.groups[$g][]' "$GEN/users.json" | sort)
  have=$(members_of "$group" | sort)
  if [ "$want" != "$have" ]; then
    log "setting members of $group"
    mapfile -t members < <(jq -r --arg g "$group" '.groups[$g][]' "$GEN/users.json")
    "$SYNOGROUP" --member "$group" "${members[@]}" >/dev/null
  fi
done < <(jq -r '.groups | keys[]' "$GEN/users.json")

# ---------------------------------------------------------------- profiles

if [ "$NIX_ENV" != true ]; then
  switch_profile() {
    local profile=$1 target=$2
    if [ "$(readlink -f "$profile" 2>/dev/null)" != "$(readlink -f "$target")" ]; then
      log "switching $profile"
      "$NIX_ENV" -p "$profile" --set "$target"
    fi
  }
  switch_profile "$ROOT/nix/var/nix/profiles/potato-bunny" "$GEN"
  if [ -e "$GEN/default-profile" ]; then
    switch_profile "$ROOT/nix/var/nix/profiles/default" "$GEN/default-profile"
  fi
fi

# ---------------------------------------------------------------- state

mkdir -p "$STATE_DIR"
units_json=$(
  for u in "${declared_units[@]}"; do
    jq -n --arg u "$u" --arg h "$(unit_hash "$u")" '{($u): $h}'
  done | jq -s 'add // {}'
)
tmp=$(mktemp "$STATE.XXXXXX")
jq -n \
  --arg gen "$GEN" \
  --argjson units "$units_json" \
  --args '{generation: $gen, etc: $ARGS.positional[0] | split("\n") | map(select(. != "")), units: $units, wants: $ARGS.positional[1] | split("\n") | map(select(. != ""))}' \
  "$(printf '%s\n' "${declared_etc[@]}")" "$(printf '%s\n' "${declared_wants[@]}")" >"$tmp"
mv -f "$tmp" "$STATE"
log "done"
