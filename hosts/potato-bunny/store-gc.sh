# Garbage-collect the Nix store when its volume runs low: below MIN_FREE bytes
# free, free enough to get back to MAX_FREE. Run by nix-store-gc.timer
# (nix-cache.nix). The store here is mostly the fleet's cache, which grows by
# incoming `nix copy` rather than local builds, so Lix's own min-free/max-free
# (checked during builds and substitutions) would rarely fire.
#
# Env: GC_PATH (a path on the store's volume), MIN_FREE, MAX_FREE (bytes),
# NIX_STORE (Lix's nix-store).
set -euo pipefail

free=$(df -B1 --output=avail "$GC_PATH" | tail -1 | tr -d ' ')
if [ "$free" -ge "$MIN_FREE" ]; then
  echo "store-gc: $((free / 1073741824)) GiB free on $GC_PATH; nothing to do"
  exit 0
fi
echo "store-gc: $((free / 1073741824)) GiB free on $GC_PATH; freeing up to $(((MAX_FREE - free) / 1073741824)) GiB"
"$NIX_STORE" --gc --max-freed "$((MAX_FREE - free))"
