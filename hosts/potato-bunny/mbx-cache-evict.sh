# Keep mbx-cache's blobs under a size cap: when the regular files under
# DATA_DIR total more than HIGH_BYTES, delete the oldest (by mtime) until they
# total LOW_BYTES or less, then sweep metadata older than the oldest blob kept.
# A blob deleted out from under its metadata is only a cache miss. Run every 6
# hours by mbx-cache-evict.timer (mbx-cache.nix); the share's quota is the hard
# ceiling behind it.
#
# Env: DATA_DIR, HIGH_BYTES, LOW_BYTES, MBX_CACHE (the server binary, which
# reads its database settings from the environment).
set -euo pipefail

# Regular files only: symlinks are neither followed nor counted. DSM's @eaDir
# index folders are skipped, and anything else unreadable is ignored rather
# than stopping eviction.
blobs() { # blobs <find -printf format>
  find "$DATA_DIR" -name @eaDir -prune -o -type f -printf "$1" 2>/dev/null || true
}

list=$(blobs '%T@ %s %p\n' | sort -n)
total=$(awk '{ s += $2 } END { print s + 0 }' <<<"$list")
if [ "$total" -le "$HIGH_BYTES" ]; then
  echo "mbx-cache-evict: $total bytes, under $HIGH_BYTES; nothing to do"
  exit 0
fi

deleted=0
while read -r _ size path; do
  [ "$total" -le "$LOW_BYTES" ] && break
  rm -f -- "$path"
  total=$((total - size))
  deleted=$((deleted + 1))
done <<<"$list"
echo "mbx-cache-evict: deleted $deleted blobs; $total bytes left"

# The minimum by awk, which reads all its input: `sort | head -1` would close
# the pipe early and, under pipefail, kill the script on a large listing.
oldest=$(blobs '%T@\n' | awk 'NR == 1 || $1 < m { m = $1 } END { if (NR) print m }')
days=1
if [ -n "$oldest" ]; then
  days=$((($(date +%s) - ${oldest%.*}) / 86400 + 1))
fi
"$MBX_CACHE" --sweep-metadata-older-than-days "$days"
