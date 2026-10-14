#!/usr/bin/env bash
# Functional smoke test + benchmark for plex.service, used to vet systemd
# sandbox settings (see plex-try.sh) and to recheck Plex after nixpkgs bumps.
#
# RUN ON NUTMEG as a sudoer (reads the Plex token from Preferences.xml):
#   bash plex-bench.sh <label>
#
# Prints a summary block and appends one JSON line to $OUT (default
# ~/.local/state/plex-bench.jsonl). PASS needs: remote access mapped, DB reads
# and a playlist create/delete, a ranged direct-play read, an image transcode,
# and forced 1080p->720p HLS transcodes of an h264 and an hevc title running on
# the full VAAPI pipeline. "denials" counts EPERM/EACCES/read-only errors
# logged by the current plex.service instance. The test titles are pinned by
# ratingKey below; repoint them if those movies leave the library.
set -uo pipefail

LABEL=${1:-run}
OUT=${OUT:-${XDG_STATE_HOME:-$HOME/.local/state}/plex-bench.jsonl}
mkdir -p "$(dirname "$OUT")"
B=http://localhost:32400
T=$(sudo grep -oP 'PlexOnlineToken="\K[^"]+' "/var/lib/plex/Plex Media Server/Preferences.xml")
H264_RK=6044   # The Hunger Games: Catching Fire (h264 1080p, DTS + EAC3)
HEVC_RK=10     # 22 Jump Street (hevc 1080p)
CID=claude-bench
declare -A R   # results
fails=()

ms() { # ms <url> : wall time of a GET in ms, or -1 on non-2xx
  local out; out=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' -H "Accept: application/json" "$1")
  [[ ${out%% *} == 2* ]] && awk -v t="${out#* }" 'BEGIN{printf "%d", t*1000}' || echo -1
}
median3() { printf '%s\n' "$@" | sort -n | sed -n 2p; }
check() { [[ $2 == ok ]] || fails+=("$1"); R[$1]=$2; }

# ── readiness: wait for Plex to answer and for plex.tv remote mapping ──
for _ in $(seq 120); do [[ $(ms "$B/identity") -ge 0 ]] && break; sleep 1; done
for _ in $(seq 90); do
  m=$(curl -s -H "Accept: application/json" "$B/myplex/account?X-Plex-Token=$T" | jq -r '.MyPlex.mappingState // empty')
  [[ $m == mapped ]] && break; sleep 2
done
check remote_access "$([[ $m == mapped ]] && echo ok || echo "fail:$m")"

# ── API / database read latency (median of 3) ──
for name_url in \
  "identity_ms|$B/identity" \
  "sections_ms|$B/library/sections?X-Plex-Token=$T" \
  "movies_page_ms|$B/library/sections/1/all?X-Plex-Container-Start=0&X-Plex-Container-Size=500&X-Plex-Token=$T" \
  "search_ms|$B/hubs/search?query=hunger&limit=10&X-Plex-Token=$T" \
  "ondeck_ms|$B/library/onDeck?X-Plex-Token=$T"; do
  n=${name_url%%|*}; u=${name_url#*|}
  R[$n]=$(median3 "$(ms "$u")" "$(ms "$u")" "$(ms "$u")")
  [[ ${R[$n]} -ge 0 ]] || fails+=("$n")
done

# ── direct play: 256 MiB ranged read of the media file over Plex (NAS → Plex → client) ──
part=$(curl -s -H "Accept: application/json" "$B/library/metadata/$H264_RK?X-Plex-Token=$T" | jq -r '.MediaContainer.Metadata[0].Media[0].Part[0].key')
r=$(curl -s -o /dev/null -r 0-268435455 -w '%{http_code} %{speed_download}' "$B$part?X-Plex-Token=$T")
[[ ${r%% *} == 206 ]] && R[direct_play_MBps]=$(awk -v s="${r#* }" 'BEGIN{printf "%.0f", s/1048576}') || { R[direct_play_MBps]=-1; fails+=(direct_play); }

# ── image transcoder (Plex Transcoder subprocess + cache write); odd width defeats the cache ──
w=$((300 + RANDOM % 200))
thumb=$(curl -s -H "Accept: application/json" "$B/library/metadata/$H264_RK?X-Plex-Token=$T" | jq -r '.MediaContainer.Metadata[0].thumb')
R[photo_transcode_ms]=$(ms "$B/photo/:/transcode?width=$w&height=$((w*3/2))&minSize=1&upscale=1&url=$(jq -rn --arg u "$thumb" '$u|@uri')&X-Plex-Token=$T")
[[ ${R[photo_transcode_ms]} -ge 0 ]] || fails+=(photo_transcode)

# ── video transcode: time-to-first-segment, speed, HW pipeline ──
vt() { # vt <prefix> <ratingKey>
  local p=$1 rk=$2 S="bench-$1-$(date +%s%N)" t0 sub seg i js
  local Q="X-Plex-Token=$T&X-Plex-Client-Identifier=$CID&X-Plex-Product=Plex%20Web&X-Plex-Platform=Chrome&X-Plex-Device=Linux&X-Plex-Session-Identifier=$S&session=$S"
  t0=$(date +%s%N)
  sub=$(curl -s "$B/video/:/transcode/universal/start.m3u8?path=%2Flibrary%2Fmetadata%2F$rk&mediaIndex=0&partIndex=0&protocol=hls&fastSeek=1&directPlay=0&directStream=0&videoResolution=1280x720&maxVideoBitrate=4000&videoQuality=60&subtitles=none&offset=600&$Q" | grep -v '^#' | head -1)
  seg=-1
  if [[ -n $sub ]]; then
    # the transcoder only starts once the client fetches the variant playlist
    curl -s -o /dev/null "$B/video/:/transcode/universal/$sub?X-Plex-Token=$T"
    for i in $(seq 100); do
      [[ $(curl -s -o /dev/null -w '%{http_code}' "$B/video/:/transcode/universal/${sub%index.m3u8}00000.ts?X-Plex-Token=$T") == 200 ]] && { seg=$(( ($(date +%s%N) - t0) / 1000000 )); break; }
      sleep 0.2
    done
  fi
  R[${p}_first_segment_ms]=$seg
  sleep 8
  js=$(curl -s -H "Accept: application/json" "$B/transcode/sessions?X-Plex-Token=$T" | jq -c --arg k "$S" '.MediaContainer.TranscodeSession[]? | select(.key==$k)')
  R[${p}_speed]=$(jq -r '.speed // -1' <<<"$js" 2>/dev/null || echo -1)
  R[${p}_hw]=$(jq -r 'if .transcodeHwFullPipeline then "full:\(.transcodeHwDecoding)/\(.transcodeHwEncoding)" else "dec=\(.transcodeHwDecoding // "sw") enc=\(.transcodeHwEncoding // "sw")" end' <<<"$js" 2>/dev/null)
  curl -s -o /dev/null "$B/video/:/transcode/universal/stop?session=$S&X-Plex-Token=$T"
  [[ $seg -ge 0 ]] || fails+=("${p}_transcode")
  [[ ${R[${p}_hw]} == full:* ]] || fails+=("${p}_hw_pipeline")
}
vt h264 $H264_RK
vt hevc $HEVC_RK

# ── database write: create + delete a playlist ──
mid=$(curl -s -H "Accept: application/json" "$B/identity" | jq -r .MediaContainer.machineIdentifier)
pl=$(curl -s -X POST -H "Accept: application/json" "$B/playlists?type=video&title=claude-bench&smart=0&uri=$(jq -rn --arg u "server://$mid/com.plexapp.plugins.library/library/metadata/$H264_RK" '$u|@uri')&X-Plex-Token=$T" | jq -r '.MediaContainer.Metadata[0].ratingKey // empty')
if [[ -n $pl ]] && [[ $(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$B/playlists/$pl?X-Plex-Token=$T") == 2* ]]; then check db_write ok; else check db_write fail; fi

# ── sandbox denials logged since this plex.service instance started ──
since=$(systemctl show plex -p ActiveEnterTimestamp --value)
R[denials]=$(journalctl -u plex --since "$since" --no-pager -o cat | grep -ciE 'permission denied|operation not permitted|read-only file system|bad system call|EACCES|EPERM')
R[score]=$(systemd-analyze security plex --no-pager 2>/dev/null | tail -1 | grep -oE '[0-9]+\.[0-9]+')

R[label]=$LABEL
R[result]=$([[ ${#fails[@]} -eq 0 ]] && echo PASS || echo "FAIL(${fails[*]})")
json=$(for k in "${!R[@]}"; do printf '%s\t%s\n' "$k" "${R[$k]}"; done | jq -Rsc 'split("\n")|map(select(length>0)|split("\t")|{(.[0]):(.[1]|tonumber? // .)})|add')
echo "$json" >> "$OUT"
printf '%-22s %s\n' label "$LABEL" result "${R[result]}" score "${R[score]}" denials "${R[denials]}" \
  remote_access "${R[remote_access]}" db_write "${R[db_write]}" \
  identity/sections/movies "${R[identity_ms]}/${R[sections_ms]}/${R[movies_page_ms]} ms" \
  search/ondeck "${R[search_ms]}/${R[ondeck_ms]} ms" direct_play "${R[direct_play_MBps]} MB/s" \
  photo_transcode "${R[photo_transcode_ms]} ms" \
  h264_transcode "first seg ${R[h264_first_segment_ms]} ms, ${R[h264_speed]}x, ${R[h264_hw]}" \
  hevc_transcode "first seg ${R[hevc_first_segment_ms]} ms, ${R[hevc_speed]}x, ${R[hevc_hw]}"
