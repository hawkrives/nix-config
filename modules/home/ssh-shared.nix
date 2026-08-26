# Shared ~/.ssh/config for the home lab. The remote usernames differ per host
# but are the same from every client, so this is worth having in one place
# rather than copied into each user's config.
{...}: {
  programs.ssh = {
    enable = true;

    # Define everything explicitly; don't inject home-manager's default global
    # options (ForwardAgent/Compression/etc.).
    enableDefaultConfig = false;

    # Loaded first, so anything here overrides the managed blocks below. Lets me
    # add a temporary host without rebuilding. Path is relative to ~/.ssh, and a
    # missing file is silently ignored by modern OpenSSH, so config.local need
    # not exist. This file is NOT managed by nix, so it stays freely editable.
    includes = ["config.local"];

    # Attribute names become `Host <name>` blocks; keys are upstream
    # ssh_config(5) directive names.
    settings = {
      potato-bunny = {
        HostName = "192.168.1.194";
        User = "hawken";
      };

      # Home lab hosts, addressed by mDNS .local names. These resolve on the
      # LAN only -- from off-LAN use the -ts aliases below, which go over the
      # tailnet. (Tailscale peers directly over the LAN when both ends are
      # local, so the -ts names are no slower at home; they just depend on
      # tailscale being up.)
      nutmeg = {
        HostName = "nutmeg.local";
        User = "natsume";
      };
      tuckles = {
        HostName = "tuckles.local";
        User = "haru";
      };
      pantry = {
        HostName = "pantry.local";
        User = "nix";
      };

      # Tailnet addresses rather than MagicDNS names: nutmeg runs
      # --accept-dns=false so MagicDNS won't resolve there, and the IPs are
      # stable. Same reasoning as modules/nixos/cache-push.nix.
      nutmeg-ts = {
        HostName = "100.70.139.99";
        User = "natsume";
      };
      tuckles-ts = {
        HostName = "100.100.204.63";
        User = "haru";
      };
      pantry-ts = {
        HostName = "100.120.197.118";
        User = "nix";
      };

      # bigpond (T2 MacBook remote builder). Fill in its LAN IP or Tailscale
      # address once it's reachable; bigpond.local wasn't advertising mDNS.
      bigpond = {
        # HostName = "bigpond.local";
        User = "pinklady";
      };
    };
  };
}
