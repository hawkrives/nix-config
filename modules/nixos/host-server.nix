{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.self.nixosModules.audit-shared
  ];

  # List services that you want to enable:
  services.openssh.enable = true;
  services.openssh.extraConfig = ''
    AcceptEnv COLORTERM
  '';

  # Open ports in the firewall.
  networking.nftables.enable = true;
  networking.firewall.enable = true;

  # TODO: does this belong here?
  networking.firewall.allowedTCPPorts = [22 80 443];

  # power management for lower idle power draw
  # TODO: why would you not enable this?
  powerManagement.powertop.enable = true;

  # packages available to all users
  environment.systemPackages = [
    pkgs.isd # TUI to work with systemd
  ];

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Basic security
  security.sudo.execWheelOnly = true;
}
