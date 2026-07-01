# Pushes every locally-built store path to the pantry cache via ssh-ng, guarded
# so an unreachable cache (offline / off-tailnet) never hangs a build. Cross-platform
# (only sets nix.settings.post-build-hook). Imported by nutmeg, tuckles, and the Mac
# (techcyte) — NOT pantry itself.
{ config, pkgs, ... }:
let
  # pantry over the tailnet. nutmeg runs --accept-dns=false, so the MagicDNS name
  # won't resolve there; the tailnet IP is stable and works on every host, and
  # tailscale still uses the direct LAN path when local.
  pantryAddr = "100.120.197.118";
  # base64 of pantry's ssh_host_ed25519_key.pub (type+key, no comment) — pins the
  # host key so no known_hosts management is needed (works on darwin + nixos).
  pantryHostKeyB64 = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUJpVVEwUGxtMmNlb25WRVJBUDBtNU5vRUgzOUozakNzdXhRZ094VzFLNjc=";
  store = "ssh-ng://nixremote@${pantryAddr}?ssh-key=/etc/ssh/ssh_host_ed25519_key&base64-ssh-public-host-key=${pantryHostKeyB64}";

  hook = pkgs.writeShellScript "cache-push-hook" ''
    set -eu
    # escape hatch: pause pushing without a rebuild
    [ -e /etc/nix/no-cache-push ] && exit 0
    # fast reachability probe — never hang a build (this hook holds a daemon build
    # slot). If pantry isn't reachable, skip silently.
    if ! ${pkgs.coreutils}/bin/timeout 2 ${pkgs.bash}/bin/bash -c 'exec 3<>/dev/tcp/${pantryAddr}/22' 2>/dev/null; then
      exit 0
    fi
    # OUT_PATHS is set by nix; a copy failure only warns, never fails the build.
    exec ${config.nix.package}/bin/nix copy --to "${store}" $OUT_PATHS
  '';
in
{
  nix.settings.post-build-hook = "${hook}";
}
