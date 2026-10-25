#!/usr/bin/env bash
# shellcheck disable=SC2029,SC2087 # remote commands embed values from this side (store paths, the boot script), on purpose
# Deploy potato-bunny (the Synology) from this machine: build the system layer
# and hawken's home-manager generation here, copy both to the NAS, then
# activate them there.
#
#   scripts/deploy-potato-bunny.sh [--ask]
#
# --ask shows the closure diff against what's running and the DSM changes
# activation would make (activate --dry-run), then waits for y/N; it
# needs a terminal, which is why mise has separate :ask and :yes tasks.
#
# Everything is built here because the NAS's CPU is slow and the closures are
# already in this machine's store. Non-login ssh on DSM has no nix on PATH,
# so remote commands use the default profile's binaries.
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
  echo "DSM changes:"
  ssh "$host" "sudo $system/bin/activate --dry-run"
  read -r -p "activate $system on $host? [y/N] " answer
  [ "$answer" = y ] || { echo "aborted"; exit 1; }
fi

# DSM runs this Task Scheduler boot-up task as root at every boot: it mounts
# /nix and /etc/nix (bind mounts of /volume1/nix, which can't move into the
# layer since they are what makes /nix exist) and re-applies the system
# layer. Its script is hosts/potato-bunny/boot-task.sh; it's set through
# DSM's own API, the same path as the Task Scheduler UI.
echo "checking the boot task…"
boot_task="Mount nix and start daemon"
ssh "$host" "sudo bash -s" <<EOF
set -euo pipefail
W=/usr/syno/bin/synowebapi
want=\$(echo '$(base64 -w0 "$flake/hosts/potato-bunny/boot-task.sh")' | base64 -d)
have=\$(\$W --exec api=SYNO.Core.EventScheduler method=get version=1 task_name='"$boot_task"' 2>/dev/null | jq -r .data.operation)
if [ "\$have" = "\$want" ]; then
  echo "boot task up to date"
else
  echo "updating boot task"
  \$W --exec api=SYNO.Core.EventScheduler method=set version=1 \\
    task_name='"$boot_task"' event='"bootup"' enable=true owner='{"0":"root"}' \\
    depend_on_task='""' operation_type='"script"' \\
    notify_enable=true notify_if_error=true notify_mail='"hawkrives@fastmail.fm"' \\
    operation="\$(jq -Rs . <<<"\$want")" 2>/dev/null | jq -e .success >/dev/null
fi
EOF

# The boot task above is synced first, so the next boot runs this
# generation's activate the way it expects to be run even if activation
# fails. A failed activation (a DSM step, say) still lets home-manager
# activate; the deploy then fails with its status.
echo "activating system layer…"
status=0
ssh "$host" "sudo $system/bin/activate" || status=$?

echo "activating home-manager for hawken…"
ssh "$host" "PATH=$remote_bin:\$PATH XDG_RUNTIME_DIR=/run/user/1027 HOME_MANAGER_BACKUP_EXT=pre-hm $home/activate"


if [ "$status" -ne 0 ]; then
  echo "system activation failed (exit $status)" >&2
  exit "$status"
fi
echo "done"
