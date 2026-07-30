#!/usr/bin/env bash
# One-time Phase-2 migration for services.channelArchive. For each channel,
# consolidate its pinchflat/<UC> + youtube/<UC> copies into a friendly dir,
# dedup by video-id (keep the pinchflat copy — it has sidecars), keep only
# English subtitles, and seed archive.txt with the union of ids so the module
# never re-downloads them.
#
# RUN ON THE SYNOLOGY as root, over SSH. The NAS NFS export is all_squash, so
# every write from the nutmeg client becomes uid 1024 and can't touch the 755
# NAS dirs — only the NAS itself has real write access. Via SSH to the NAS:
#   sudo env DRYRUN=1 CHANNELS_ROOT=/volume1/media-channels bash channel-archive-migrate.sh  # preview
#   sudo env CHANNELS_ROOT=/volume1/media-channels bash channel-archive-migrate.sh           # perform
#
# Each dest dir is created group-writable + setgid + group users(100), so the
# nutmeg module (writing as the squashed 1024:users) can add downloads later
# and Plex/Jellyfin can read them.
#
# CHANNELS_ROOT overrides /mnt/channels (tests point it at a temp dir).
# DRYRUN=1 prints intended ops without touching the fs.
#
# Re-runs are safe: seed_archive() is non-destructive (skips any dest that
# already has an archive.txt, so it never clobbers ids the module has since
# appended), and dedup keys (collect_ids) are snapshotted only from pinchflat
# VIDEO files, never sidecars, so an orphan sidecar can't delete a real video.
#
# Portable: pure-bash parameter expansion (no GNU find -printf, basename, or
# sed), so it runs on DSM's bash as well as GNU/Linux.
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
id_of() { local b="${1##*/}"; printf '%s' "${b%%.*}"; }

# Subtitle handling: pinchflat pulled auto-translated subs in ~100 languages
# (.srt/.vtt) per video. Keep only English tracks (en / en-orig / en-*), drop
# the rest — consistent with the module's no-subtitles policy and to keep
# Plex/Jellyfin from showing 100+ subtitle tracks per video.
is_sub() { case "$1" in *.srt | *.vtt) return 0 ;; *) return 1 ;; esac; }
is_english_sub() { local x="${1%.srt}"; x="${x%.vtt}"; case "${x##*.}" in en | en-* | en_*) return 0 ;; *) return 1 ;; esac; }

# Print the video-id (basename up to first '.') of each video file directly
# under $1, one per line. Pure-glob, no GNU find.
video_ids_in() {
  local dir="$1" f b
  for f in "$dir"/*.mp4 "$dir"/*.mkv "$dir"/*.webm; do
    [ -e "$f" ] || continue
    b="${f##*/}"
    printf '%s\n' "${b%%.*}"
  done
}

# Snapshot pinchflat's VIDEO ids into the caller's pf_ids assoc array *before*
# the youtube loop moves files in, so a youtube sibling (e.g. a .vtt sorting
# ahead of its .mp4) is never mistaken for a pinchflat original. VIDEO files
# only — an orphan sidecar must never contribute a dedup key, else a real,
# sidecar-less youtube video of the same id would be wrongly deleted.
collect_ids() {
  local id
  while IFS= read -r id; do
    [ -n "$id" ] && pf_ids["$id"]=1
  done < <(video_ids_in "$1")
}

seed_archive() {
  local dest="$1"
  local archive="$dest/archive.txt"
  if [ -e "$archive" ]; then log "  archive.txt exists, leaving as-is -> $archive"; return; fi
  if [ "$DRYRUN" = 1 ]; then log "  DRY: would seed archive.txt -> $archive"; return; fi
  local id
  video_ids_in "$dest" | sort -u | while IFS= read -r id; do printf 'youtube %s\n' "$id"; done > "$archive"
  chmod 664 "$archive"
  chgrp 100 "$archive" 2>/dev/null || true
  log "  seeded $(wc -l < "$archive") ids -> $archive"
}

migrate_one() {
  local uc="$1" name="$2"
  local dest="$ROOT/$name" pf="$ROOT/pinchflat/$uc" yt="$ROOT/youtube/$uc"
  local moved=0 deduped=0 dropped=0 f id bn
  local -A pf_ids=()
  log "=== $name  ($uc) ==="
  run mkdir -p "$dest"
  # setgid + group-writable + group users(100): lets the nutmeg module (writing
  # as the squashed 1024:users) create files here, inheriting group users.
  run chgrp 100 "$dest"
  run chmod 2775 "$dest"
  if [ -d "$pf" ]; then
    for f in "$pf"/*; do
      [ -e "$f" ] || continue
      bn="${f##*/}"
      if is_sub "$bn" && ! is_english_sub "$bn"; then
        run rm -f -- "$f"; dropped=$((dropped+1)); continue
      fi
      run mv -- "$f" "$dest/"; moved=$((moved+1))
    done
  fi
  [ "$DRYRUN" != 1 ] && collect_ids "$dest"
  if [ -d "$yt" ]; then
    for f in "$yt"/*; do
      [ -e "$f" ] || continue
      bn="${f##*/}"
      if is_sub "$bn" && ! is_english_sub "$bn"; then
        run rm -f -- "$f"; dropped=$((dropped+1)); continue
      fi
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
  log "  moved=$moved deduped=$deduped dropped-subs=$dropped"
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
