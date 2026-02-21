{
  flake,
  hostName,
  pkgs,
  ...
}: {
  imports = [
    flake.nixosModules.host-shared
    flake.nixosModules.host-server
    flake.nixosModules.host-nixos
    flake.nixosModules.veilid-shared
    # flake.nixosModules.pocket-id
    # flake.nixosModules.pomerium

    # configuration
    ./hardware.nix

    # modules
    ./adguard.nix
    ./home-assistant.nix
    ./home-assistant-matter.nix
    ./plex.nix
    ./tailscale.nix
    ./syncthing.nix
    ./paperless.nix
    ./nix-serve.nix
    # ./peertube.nix
    ./discourse.nix
    ./micasa.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = hostName; # hostName is detected by Blueprint; defaults to the containing folder's name

  services.mbpfan.enable = true; # enable Mac fan control daemon
  systemd.coredump.enable = false; # disable core dumps

  users.users."natsume" = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.fish;
  };

  users.groups.techcyte = {};
  users.users.techcyte = {
    isNormalUser = true;
    group = "techcyte";
    shell = pkgs.fish;

    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7JcUKxjlOrnEmQb7MgUmEZnTh8HPUoy84n5tmK4Ivs4aSpP6Q6Yh7OUCYRWjLHNGzXtRKqEgalDd8406KHvqcbDMs9LrR6ld0IlwVJpyibgs/wpukBzXJZgTaj3xXKhzFLECbxLey0EbJ/GHOXdywHKy1QQNs97PdtzK0XQazakQktp++V6MgRcCrzbTPTZVLcySlolSNpNFR4kAUVYK2xXKM145k74vKAoijsfWLBbNSXnx2sNYjKhWc2kpgiIDoJru9viFOIZZX0IJc/o9DT5eR+KoCNHTu5ioZ1x+Y8xSoVTFr+hjuQjZ3NFXeQ9sn08SjZtTsBZpDkJhI17hIEfPJ1vf4QDhS8Bz4yiaqiPMQ8j5Fr7ewa2zmT6Ocfk0rbseHXxZy91grQvl1NsMLGmzcdRd168Zv8du0OTHa4qu7vCUoLdx8S+NPnO57+QNxQDB97WFTBRjWxtbPcAKwBHjo3/zhW8ekFhtKEzdKCTlKd5N5E2UuIVsFE2O2itE= hawken@potato-bunny"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5cvA90dd+syRxeLBrQEdwBGmM4kC4pZBcbnya1g5sw natsume@nutmeg"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILFhbHFf1LJ/NseB3yDEAKNu3CGNDs+ot8qdQA5LI4rU hawken.rives@Techcyte-DGQJV434PF"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGKeWabODTfpiljiMRYVD7FFk8sQQgaKFqZMHo6iyfKjeN4868IuJBZ78euIbM4ztXy/JICW6oVhfPifAm9d3Jk= ECD-ShellFish@Long-Blippp-30122023"
    ];
  };

  programs.nh = {
    flake = "/home/natsume/nix-config#${hostName}";
    clean.enable = true;
    clean.dates = "weekly";
    clean.extraArgs = "--keep-since 4d --keep 3";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
