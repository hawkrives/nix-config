{
  pkgs,
  flake,
  ...
}: {
  imports = [
    flake.nixosModules.audit-shared
    flake.nixosModules.documentation
  ];

  # openssh automatically opens its port
  services.openssh.enable = true;
  services.openssh.startWhenNeeded = true; # socket-activated daemon
  services.openssh.extraConfig = ''
    AcceptEnv COLORTERM
  '';

  # enable .local domain resolution
  services.avahi = {
    enable = true;
    publish.enable = true;
    # register a mDNS HINFO record which contains information about the local operating system and CPU
    publish.hinfo = true;
    # Needed to allow samba to automatically register mDNS records (without the need for an `extraServiceFile`
    publish.userServices = true;
    # allows applications to resolve names in the `.local` domain by transparently querying the Avahi daemon.
    nssmdns4 = true;
    # Due to the fact that most mDNS responders only register local IPv4
    # addresses, most user want to leave this option disabled to avoid long timeouts
    # when applications first resolve the none existing IPv6 address.
    nssmdns6 = true;
  };

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
