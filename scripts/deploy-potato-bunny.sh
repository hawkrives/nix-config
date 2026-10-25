#!/usr/bin/env bash
# shellcheck disable=SC2029 # remote commands embed store paths built on this side, on purpose
# Deploy potato-bunny (the Synology) from this machine: build the system layer
# and hawken's home-manager generation here, copy both to the NAS, then
# activate them there.
#
#   scripts/deploy-potato-bunny.sh [--ask]
#
# --ask shows the closure diff against what's running and waits for y/N; it
# needs a terminal, which is why mise has separate :ask and :yes tasks.
#
# Everything is built here because the NAS can't reach pantry (DSM's
# tailscale is userspace-only) and its CPU is slow. Non-login ssh on DSM has
# no nix on PATH, so remote commands use the default profile's binaries.
set -euo pipefail

ask=false
[ "${1:-}" = --ask ] && ask=true

host=potato-bunny
remote_bin=/nix/var/nix/profiles/default/bin
store="ssh-ng://$host?remote-program=$remote_bin/nix-daemon"
flake=$(cd "$(dirname "$0")/.." && pwd)

echo "building on $(hostname)…"
mapfile -t paths < <(nix build --no-link --print-out-paths \
  "$flake#potato-bunny-system" \
  "$flake#legacyPackages.x86_64-linux.homeConfigurations.\"hawken@$host\".activationPackage")
system=${paths[0]}
home=${paths[1]}

echo "copying to $host…"
# hawken is a trusted user on the NAS.
nix copy --no-check-sigs --to "$store" "$system" "$home"

if $ask; then
  current=$(ssh "$host" "readlink -f /nix/var/nix/profiles/potato-bunny || true")
  if [ -n "$current" ]; then
    ssh "$host" "$remote_bin/nix store diff-closures '$current' '$system'" || true
  else
    echo "(first activation: no current system generation)"
  fi
  read -r -p "activate $system on $host? [y/N] " answer
  [ "$answer" = y ] || { echo "aborted"; exit 1; }
fi

echo "activating system layer…"
ssh "$host" "sudo $system/bin/activate"

echo "activating home-manager for hawken…"
ssh "$host" "PATH=$remote_bin:\$PATH XDG_RUNTIME_DIR=/run/user/1027 HOME_MANAGER_BACKUP_EXT=pre-hm $home/activate"

echo "done"
