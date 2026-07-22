{
  pkgs,
  inputs,
  ...
}: {
  # config settings only applicable to NixOS-based systems, not Darwin
  imports = [
    inputs.ragenix.nixosModules.default
  ];

  programs.neovim = {
    enable = true;
    package = pkgs.neovim-unwrapped;
    withRuby = false;
    withNodeJs = false;
    withPython3 = false;
    vimAlias = true;
    viAlias = true;
  };

  # enable the nice nh tool (reimplements darwin-rebuild, nixos-rebuild, etc)
  # <https://schmiggolas.dev/posts/2024/nh/>
  programs.nh.enable = true;

  # [memory management] zswap + systemd-oomd, applied to every Linux host.
  #
  # zswap is a compressed writeback cache that sits in FRONT of real disk swap:
  # hot anonymous pages are compressed in RAM, and cold ones are evicted down to
  # the swapfile (defined per-host, since each host picks its own size). This
  # replaces the old standalone zramSwap, which had no backing store — under
  # sustained memory pressure it could only OOM or hang for minutes rather than
  # tier cold pages to disk.
  # https://chrisdown.name/2026/03/24/zswap-vs-zram-when-to-use-what.html
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
    "zswap.max_pool_percent=20"
  ];

  # systemd-oomd is enabled by default in NixOS, but NixOS ships it with every
  # slice monitor OFF, so the daemon runs without ever acting. Turn on all three
  # so oomd kills the worst-offending cgroup under real memory/swap pressure,
  # before the kernel OOM killer (or a multi-minute brownout) would.
  systemd.oomd = {
    enableRootSlice = true;
    enableSystemSlice = true;
    enableUserSlices = true;
  };

  # enables the "virtualisation.oci-containers.containers" namespace for running containers
  virtualisation.oci-containers.backend = "podman";
  virtualisation.podman = {
    enable = true;

    # periodically prune Podman resources
    autoPrune.enable = true;
    # Create a `docker` alias for podman, to use it as a drop-in replacement
    dockerCompat = true;

    # Required for containers under podman-compose to be able to talk to each other.
    # defaultNetwork.settings.dns_enabled = true;
  };
}
