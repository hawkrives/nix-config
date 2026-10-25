# Keeping nutmeg's SSD writes down. Its only disk is a 250 GB Samsung 860 EVO
# past its rated endurance (SMART "Percentage Used" 123% in 2026-10), so the
# biggest avoidable writers go elsewhere.
{...}: {
  # Lix's build directory (build-dir = /nix/var/nix/b) in RAM: build scratch
  # space is written, read once and deleted, which costs SSD wear and buys
  # nothing. The cap (20G) is above RAM (16 GB): small builds stay in memory,
  # and a big one spills into swap (the 8 GB /swapfile, on the SSD) instead of
  # failing; only past 20G does it fail with "No space left on device".
  fileSystems."/nix/var/nix/b" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = ["size=20G" "mode=0755"];
  };
}
