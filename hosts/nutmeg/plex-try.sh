#!/usr/bin/env bash
# Try candidate [Service] settings on plex.service without a rebuild: writes
# them to a runtime drop-in (/run/systemd/system/plex.service.d/, gone on
# reboot), restarts Plex, and runs plex-bench.sh against it.
#
# RUN ON NUTMEG as a sudoer:
#   bash plex-try.sh <label> Key=Value [Key=Value ...]   # test settings
#   bash plex-try.sh <label>                             # drop the test drop-in
#
# Refuses to restart while anyone is streaming. Results land in the same
# $OUT as plex-bench.sh. Run it with no settings when done, or the drop-in
# keeps overriding the deployed unit until reboot.
set -uo pipefail
DIR=$(dirname "$0")
LABEL=$1; shift
D=/run/systemd/system/plex.service.d
T=$(sudo grep -oP 'PlexOnlineToken="\K[^"]+' "/var/lib/plex/Plex Media Server/Preferences.xml")

n=$(curl -s -H "Accept: application/json" "http://localhost:32400/status/sessions?X-Plex-Token=$T" | jq -r '.MediaContainer.size // 0')
n=${n:-0}
if [[ $n != 0 ]]; then echo "SKIP $LABEL: $n active stream(s)"; exit 2; fi

sudo mkdir -p $D
if [[ $# -gt 0 ]]; then
  { echo "[Service]"; printf '%s\n' "$@"; } | sudo tee $D/zz-hardening-test.conf >/dev/null
else
  sudo rm -f $D/zz-hardening-test.conf
fi
sudo systemctl daemon-reload

# Fast restart: let the main server shut down cleanly on SIGQUIT (closes its DBs),
# then SIGKILL the helpers (Script Host, DLNA, EasyAudioEncoder) that ignore it.
main=$(pgrep -x "Plex Media Serv" | head -1)
sudo systemctl stop --no-block plex
for _ in $(seq 60); do [[ -n $main ]] && sudo test -d /proc/$main || break; sleep 0.5; done
sudo systemctl kill -s SIGKILL plex 2>/dev/null
for _ in $(seq 30); do [[ $(systemctl show plex -p ActiveState --value) == inactive || $(systemctl show plex -p ActiveState --value) == failed ]] && break; sleep 0.5; done
sudo systemctl reset-failed plex 2>/dev/null
sudo systemctl start plex
sleep 3
if [[ $(systemctl show plex -p ActiveState --value) != active ]]; then
  echo "label                  $LABEL"; echo "result                 FAIL(unit not active)"
  journalctl -u plex -n 15 --no-pager -o cat | sed 's/^/  | /'
  echo "{\"label\":\"$LABEL\",\"result\":\"FAIL(unit not active)\"}" >> "${OUT:-${XDG_STATE_HOME:-$HOME/.local/state}/plex-bench.jsonl}"
  exit 1
fi
bash "$DIR/plex-bench.sh" "$LABEL"
