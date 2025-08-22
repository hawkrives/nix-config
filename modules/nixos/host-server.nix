{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.self.nixosModules.audit-shared
    inputs.self.nixosModules.documentation
  ];

  # openssh automatically opens its port
  services.openssh.enable = true;
  services.openssh.extraConfig = ''
    AcceptEnv COLORTERM
  '';

  # allow you to track your highest uptimes
  services.uptimed.enable = true;

  # Open ports in the firewall.
  networking.nftables.enable = true;
  networking.firewall.enable = true;

  # power management for lower idle power draw
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
