# Bring a systemd user manager in line with a new home-manager generation,
# without sd-switch: DSM has no user D-Bus for it to talk to, and its systemd
# is 219, so this drives DSM's own systemctl over the manager's private socket.
#
# Usage: dsm-user-units <old units dir> <new units dir>
#   (each is <generation>/home-files/.config/systemd/user; old may not exist)
#
# - new units wanted by default.target are started
# - changed units are restarted if running (try-restart)
# - units gone from the new generation are stopped
OLD=$1
NEW=$2
SYSTEMCTL=${SYSTEMCTL:-/usr/bin/systemctl}

sc() { "$SYSTEMCTL" --user "$@"; }

units_in() { # units_in <dir>: unit file names directly in dir
  [ -d "$1" ] || return 0
  local f
  for f in "$1"/*; do
    [ -f "$f" ] && basename "$f"
  done
  return 0
}

sc daemon-reload

for name in $(units_in "$NEW"); do
  if [ -e "$OLD/$name" ]; then
    if ! cmp -s "$OLD/$name" "$NEW/$name"; then
      echo "restarting $name"
      sc try-restart "$name" || echo "warning: restarting $name failed" >&2
    fi
  elif [ -e "$NEW/default.target.wants/$name" ]; then
    echo "starting $name"
    sc start "$name" || echo "warning: starting $name failed" >&2
  fi
done

for name in $(units_in "$OLD"); do
  if [ ! -e "$NEW/$name" ]; then
    echo "stopping $name"
    sc stop "$name" || echo "warning: stopping $name failed" >&2
  fi
done
