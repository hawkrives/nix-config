{flake, ...}: {
  imports = [
    flake.homeModules.home-shared
    flake.homeModules.git-shared
    flake.homeModules.jj-shared
    flake.homeModules.jjui-shared
    flake.homeModules.helix-shared
    flake.homeModules.sqlite-shared
  ];

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

      # Home lab hosts (mDNS .local names, resolvable on the LAN).
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

      # bigpond (T2 MacBook remote builder). Fill in its LAN IP or Tailscale
      # address once it's reachable; bigpond.local wasn't advertising mDNS.
      bigpond = {
        # HostName = "bigpond.local";
        User = "pinklady";
      };
    };
  };
}
