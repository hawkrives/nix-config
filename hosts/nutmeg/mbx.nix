# Client side of the mbx remote cache on pantry (hosts/pantry/mbx-cache.nix);
# the per-user half is modules/home/mbx-shared.nix.
{...}: {
  age.secrets.mbx-token = {
    file = ../../secrets/mbx-token-nutmeg.age;
    owner = "natsume";
  };

  # The cache's TLS certificate is for pantry's MagicDNS name, and nutmeg runs
  # --accept-dns=false (tailscale.nix), so that name doesn't resolve here
  # unless it's pinned. Same tailnet IP cache-push.nix uses.
  networking.hosts."100.120.197.118" = ["pantry.vaquita-woodpecker.ts.net"];
}
