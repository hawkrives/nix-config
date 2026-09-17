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

  # Same key host-shared.nix hands to nix.settings.secret-key-files. Read from
  # age.secrets rather than `config.nix.settings.secret-key-files`: reading
  # nix.settings from a module that *defines* nix.settings.post-build-hook
  # forces the submodule through itself and evaluation dies with infinite
  # recursion. age.secrets is a separate option tree, so it composes fine.
  keyFile = config.age.secrets.nix-signing-key.path;

  hook = pkgs.writeShellScript "cache-push-hook" ''
    set -eu

    # Sign the whole closure, before anything below can bail out.
    #
    # Two gaps let a path pantry cannot verify sit in our store. Nix only signs
    # automatically for builds that actually ran here
    # (LocalDerivationGoal::registerOutputs -> signPathInfo); the generic
    # DerivationGoal used when build-remote delegates never signs. And a path
    # substituted from a cache pantry does not know — Techcyte's attic, on the
    # Mac — carries only that cache's signature.
    #
    # --recursive rather than just $OUT_PATHS, because nix copy sends the whole
    # closure and one unverifiable dependency refuses the entire push. Pantry's
    # daemon does log this connection as a trusted user, but that buys nothing:
    # ssh-ng runs `nix-daemon --stdio` as nixremote, and that process cannot
    # authenticate its stdio peer, so it serves us as untrusted and asks the
    # real daemon to check signatures regardless of trusted-users.
    #
    # Signing is also what makes a pushed path worth having: pantry keeps the
    # signatures, and every host's require-sigs checks them on the way back
    # out, so a path stored there unsigned is one nobody can substitute.
    # Idempotent on paths already carrying this key, and never worth failing a
    # build over.
    ${config.nix.package}/bin/nix store sign --recursive --key-file ${keyFile} $OUT_PATHS || true

    # escape hatch: pause pushing without a rebuild
    [ -e /etc/nix/no-cache-push ] && exit 0
    # fast reachability probe — never hang a build (this hook holds a daemon build
    # slot). If pantry isn't reachable, skip silently.
    if ! ${pkgs.coreutils}/bin/timeout 2 ${pkgs.bash}/bin/bash -c 'exec 3<>/dev/tcp/${pantryAddr}/22' 2>/dev/null; then
      exit 0
    fi
    # OUT_PATHS is set by nix. A push is an optimisation, never a build
    # requirement, so a copy failure warns and the hook still exits 0 — nix
    # fails the build on any non-zero exit from a post-build-hook, so `exec`
    # here (which hands nix copy's status straight to nix) turned an
    # unreachable or unhappy cache into a broken local build.
    if ! ${config.nix.package}/bin/nix copy --to "${store}" $OUT_PATHS; then
      echo "cache-push: pushing to pantry failed; continuing" >&2
    fi
    exit 0
  '';
in
{
  nix.settings.post-build-hook = "${hook}";
}
