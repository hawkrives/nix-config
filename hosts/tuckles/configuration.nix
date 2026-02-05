{ flake, hostName, config, pkgs, ... }:

{
  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = hostName;
  networking.useNetworkd = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  swapDevices = [];
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  users.users.haru = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.fish;

    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7JcUKxjlOrnEmQb7MgUmEZnTh8HPUoy84n5tmK4Ivs4aSpP6Q6Yh7OUCYRWjLHNGzXtRKqEgalDd8406KHvqcbDMs9LrR6ld0IlwVJpyibgs/wpukBzXJZgTaj3xXKhzFLECbxLey0EbJ/GHOXdywHKy1QQNs97PdtzK0XQazakQktp++V6MgRcCrzbTPTZVLcySlolSNpNFR4kAUVYK2xXKM145k74vKAoijsfWLBbNSXnx2sNYjKhWc2kpgiIDoJru9viFOIZZX0IJc/o9DT5eR+KoCNHTu5ioZ1x+Y8xSoVTFr+hjuQjZ3NFXeQ9sn08SjZtTsBZpDkJhI17hIEfPJ1vf4QDhS8Bz4yiaqiPMQ8j5Fr7ewa2zmT6Ocfk0rbseHXxZy91grQvl1NsMLGmzcdRd168Zv8du0OTHa4qu7vCUoLdx8S+NPnO57+QNxQDB97WFTBRjWxtbPcAKwBHjo3/zhW8ekFhtKEzdKCTlKd5N5E2UuIVsFE2O2itE= hawken@potato-bunny"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5cvA90dd+syRxeLBrQEdwBGmM4kC4pZBcbnya1g5sw natsume@nutmeg"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILFhbHFf1LJ/NseB3yDEAKNu3CGNDs+ot8qdQA5LI4rU hawken.rives@Techcyte-DGQJV434PF"
    ];
  };

  environment.systemPackages = with pkgs; [
    cowsay
    lolcat
  ];

  programs.fish.enable = true;

  programs.nh = {
    enable = true;
    # todo: flake = "path#${hostName}";
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep-since 4d --keep 3";
    };
  };

  services.openssh = {
    enable = true;
    # require public key authentication for better security
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
  };

  system.stateVersion = "25.11";
}
