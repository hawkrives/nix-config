# IPv6 forwarding for the tailnet exit node (tailscale.nix advertises ::/0).
#
#   ipv6-forwarding.sh on|off   (CONF overrides /proc/sys/net/ipv6/conf for tests)
#
# With forwarding on, an interface whose accept_ra is 1 stops accepting router
# advertisements, and the NAS would lose its SLAAC address and default route
# when they expire. So first every interface taking advertisements gets 2,
# which takes them even while forwarding. Interfaces that took none are left
# alone.
set -euo pipefail
CONF=${CONF:-/proc/sys/net/ipv6/conf}

case "${1:-}" in
  on)
    for f in "$CONF"/*/accept_ra; do
      i=$(basename "$(dirname "$f")")
      case "$i" in all | default | lo) continue ;; esac
      [ "$(cat "$f")" = 1 ] && echo 2 >"$f"
    done
    echo 1 >"$CONF/all/forwarding"
    ;;
  off) echo 0 >"$CONF/all/forwarding" ;;
  *) echo "usage: $0 on|off" >&2; exit 2 ;;
esac
