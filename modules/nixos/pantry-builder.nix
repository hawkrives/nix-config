# Uses the pantry cache VM as an x86_64-linux remote builder over the tailnet.
# Reuses the exact same nixremote SSH identity + pinned host key as the cache
# push/pull (see cache-push.nix and host-shared.nix): the client's own host key
# authenticates as the trusted `nixremote` user on pantry, and pantry's host key
# is pinned inline so no known_hosts management is needed. Cross-platform (only
# sets nix.buildMachines / nix.distributedBuilds), so it works on darwin too.
# Imported by the Mac (techcyte), which has no local Linux builder.
{ ... }:
let
  # pantry over the tailnet — same stable IP used by the cache config (nutmeg runs
  # --accept-dns=false, so MagicDNS won't resolve there; the tailnet IP always does).
  pantryAddr = "100.120.197.118";
  # base64 of pantry's ssh_host_ed25519_key.pub (type+key, no comment) — pins the
  # builder's host key. Same literal as cache-push.nix / host-shared.nix.
  pantryHostKeyB64 = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUJpVVEwUGxtMmNlb25WRVJBUDBtNU5vRUgzOUozakNzdXhRZ094VzFLNjc=";
in
{
  nix.distributedBuilds = true;
  # let pantry pull build inputs from the public caches itself instead of the
  # client uploading every dependency over ssh.
  nix.settings.builders-use-substitutes = true;

  nix.buildMachines = [
    {
      hostName = pantryAddr;
      sshUser = "nixremote";
      sshKey = "/etc/ssh/ssh_host_ed25519_key";
      systems = [ "x86_64-linux" ];
      publicHostKey = pantryHostKeyB64;
      maxJobs = 4;
      speedFactor = 2;
      supportedFeatures = [ "kvm" ];
    }
  ];
}
