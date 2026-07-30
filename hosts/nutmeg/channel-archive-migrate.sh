#!/usr/bin/env bash
# One-time Phase-2 migration for services.channelArchive. For each channel,
# consolidate its pinchflat/<UC> + youtube/<UC> copies into a friendly dir,
# dedup by video-id (keep the pinchflat copy — it has sidecars), and seed
# archive.txt with the union of ids so the module never re-downloads them.
#
# Run AS plex (owns /mnt/channels; root is NFS-squashed here):
#   sudo -u plex env DRYRUN=1 bash channel-archive-migrate.sh   # coarse preview
#   sudo -u plex bash channel-archive-migrate.sh                 # perform
#
# CHANNELS_ROOT overrides /mnt/channels (tests point it at a temp dir).
# DRYRUN=1 prints intended ops without touching the fs (coarse: does not
# simulate dedup/seed against a not-yet-populated dest).
set -uo pipefail

ROOT="${CHANNELS_ROOT:-/mnt/channels}"
DRYRUN="${DRYRUN:-0}"

# "<UC id>=<friendly dir name under $ROOT>"
CHANNELS=(
  "UCedsCHD4XKPg5YiK56jTypg=Settei Seven"
  "UCzd7kTq1TCKOA6kPWaW2Z8Q=Axell The Swampert"
  "UCjQSQVa1-OgDmp4ypfdRbWQ=jen"
  "UCAHPCNxU4A-TUV-lnu7u4tA=adrisaurus"
  "UCWoSKWs8h6lFdiEDAjuIfpA=Displaced Gamers"
  "UCDzdRLILLWlHxXnj3HhXW0A=Caitlin Myers"
)

log() { printf '%s\n' "$*"; }
run() { if [ "$DRYRUN" = 1 ]; then log "  DRY: $*"; else "$@"; fi; }
id_of() { local b; b="$(basename -- "$1")"; printf '%s' "${b%%.*}"; }

# Populate the pf_ids assoc array (declared by the caller) with the video-ids
# already present in $1. Used to snapshot pinchflat's ids *before* the youtube
# loop starts moving files in, so youtube siblings (e.g. a .vtt moved ahead of
# its .mp4 by glob order) never get mistaken for a pinchflat original.
collect_ids() {
  local dir="$1" f
  for f in "$dir"/*; do
    [ -e "$f" ] || continue
    pf_ids["$(id_of "$f")"]=1
  done
}

seed_archive() {
  local dest="$1" archive="$dest/archive.txt"
  if [ "$DRYRUN" = 1 ]; then log "  DRY: would seed archive.txt -> $archive"; return; fi
  find "$dest" -maxdepth 1 -type f \
       \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' \) \
       -printf '%f\n' 2>/dev/null | sed 's/\..*$//' | sort -u \
    | sed 's/^/youtube /' > "$archive"
  chmod 664 "$archive"
  log "  seeded $(wc -l < "$archive") ids -> $archive"
}

migrate_one() {
  local uc="$1" name="$2"
  local dest="$ROOT/$name" pf="$ROOT/pinchflat/$uc" yt="$ROOT/youtube/$uc"
  local moved=0 deduped=0 f id
  local -A pf_ids=()
  log "=== $name  ($uc) ==="
  run mkdir -p "$dest"
  run chmod 775 "$dest"
  if [ -d "$pf" ]; then
    for f in "$pf"/*; do
      [ -e "$f" ] || continue
      run mv -- "$f" "$dest/"; moved=$((moved+1))
    done
  fi
  # Snapshot pinchflat's ids *before* the youtube loop mutates $dest, so a
  # youtube file never gets deduped against a sibling moved earlier in the
  # same loop (e.g. a .vtt sorting ahead of its .mp4) — only against a true
  # pinchflat original.
  [ "$DRYRUN" != 1 ] && collect_ids "$dest"
  if [ -d "$yt" ]; then
    for f in "$yt"/*; do
      [ -e "$f" ] || continue
      id="$(id_of "$f")"
      if [ "$DRYRUN" != 1 ] && [ -n "${pf_ids[$id]:-}" ]; then
        run rm -f -- "$f"; deduped=$((deduped+1))
      else
        run mv -- "$f" "$dest/"; moved=$((moved+1))
      fi
    done
  fi
  seed_archive "$dest"
  [ -d "$pf" ] && { run rmdir "$pf" 2>/dev/null || log "  note: $pf not empty, left in place"; }
  [ -d "$yt" ] && { run rmdir "$yt" 2>/dev/null || log "  note: $yt not empty, left in place"; }
  log "  moved=$moved deduped=$deduped"
}

main() {
  log "channel-archive migration (ROOT=$ROOT DRYRUN=$DRYRUN)"
  local entry
  for entry in "${CHANNELS[@]}"; do
    migrate_one "${entry%%=*}" "${entry#*=}"
  done
  log "done."
}

# Only auto-run when executed directly; tests source this file and call functions.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then main "$@"; fi
