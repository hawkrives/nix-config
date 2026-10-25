# Give nix-tailscaled the Synology package's Tailscale state, once: if NEW has
# no tailscaled.state and OLD does, copy OLD's contents (identity, serve
# config, certs; not its socket, pid or logs) into NEW, owned by root. Keeps
# the node, and so its tailnet IP. Never touches a NEW that already has state.
#
# Usage: tailscale-migrate.sh OLD NEW   (CHOWN overridable for tests)
set -euo pipefail
old=$1 new=$2
CHOWN=${CHOWN:-chown}

[ -e "$new/tailscaled.state" ] && exit 0
if [ ! -e "$old/tailscaled.state" ]; then
  echo "tailscale-migrate: no state in $old; starting fresh"
  exit 0
fi

echo "tailscale-migrate: copying $old into $new"
mkdir -p "$new"
chmod 0700 "$new"
(cd "$old" && find . -mindepth 1 -maxdepth 1 \
  ! -name '*.sock' ! -name '*.pid' ! -name '*.log' \
  -exec cp -a {} "$new/" \;)
"$CHOWN" -R 0:0 "$new"
