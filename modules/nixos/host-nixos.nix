{
  pkgs,
  inputs,
  ...
}: {
  # config settings only applicable to NixOS-based systems, not Darwin
  imports = [
    inputs.agenix.nixosModules.default
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

  # [disk] Wipe /tmp at boot. Nothing here treats /tmp as durable, and without
  # this nothing ever reaps it — it accumulates indefinitely on hosts whose
  # root filesystems are not roomy.
  boot.tmp.cleanOnBoot = true;

  # [disk] cap the journal. journald's default ceiling is 10% of the filesystem,
  # which on nutmeg's 187G root meant ~18G of headroom and a journal that had
  # grown to 4G unnoticed. These hosts are not log-archival machines — anything
  # worth keeping past a few weeks belongs in a backup, not the ring buffer.
  services.journald.extraConfig = ''
    SystemMaxUse=1G
    MaxRetentionSec=1month
  '';

  # enables the "virtualisation.oci-containers.containers" namespace for running containers
  virtualisation.oci-containers.backend = "podman";
  virtualisation.podman = {
    enable = true;

    # periodically prune Podman resources. `--all` is load-bearing: the bare
    # `podman system prune` this runs by default only reaps *dangling* images,
    # so images that are still tagged but no longer referenced by a container
    # accumulate forever (nutmeg had 4.9G of them). Note this deliberately does
    # NOT pass `--volumes` — named volumes hold real service state, and pruning
    # them because nothing is currently running would be data loss.
    autoPrune.enable = true;
    autoPrune.flags = [ "--all" ];
    # Create a `docker` alias for podman, to use it as a drop-in replacement
    dockerCompat = true;

    # Required for containers under podman-compose to be able to talk to each other.
    # defaultNetwork.settings.dns_enabled = true;
  };
}
