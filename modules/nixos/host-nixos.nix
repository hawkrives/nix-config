{perSystem, ...}: {
  # config settings only applicable to NixOS-based systems, not Darwin

  programs.neovim = {
    enable = true;
    package = perSystem.nixpkgs-unstable.neovim-unwrapped;
    withRuby = false;
    withNodeJs = false;
    withPython3 = false;
    vimAlias = true;
    viAlias = true;
  };

  # enable the nice nh tool (reimplements darwin-rebuild, nixos-rebuild, etc)
  # <https://schmiggolas.dev/posts/2024/nh/>
  programs.nh = {
    enable = true;
    package = perSystem.nixpkgs-unstable.nh;
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
