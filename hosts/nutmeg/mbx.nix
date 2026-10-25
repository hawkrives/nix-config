# Client side of the mbx remote cache on potato-bunny
# (hosts/potato-bunny/mbx-cache.nix); the per-user half is modules/home/mbx-shared.nix.
{...}: {
  age.secrets.mbx-token = {
    file = ../../secrets/mbx-token-nutmeg.age;
    owner = "natsume";
  };

  # The cache's TLS certificate is for potato-bunny's MagicDNS name, and nutmeg runs
  # --accept-dns=false (tailscale.nix), so that name doesn't resolve here
  # unless it's pinned. Same tailnet IP cache-push.nix uses.
  networking.hosts."100.111.251.156" = ["potato-bunny.vaquita-woodpecker.ts.net"];
}
