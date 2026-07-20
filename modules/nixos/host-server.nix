{
  pkgs,
  flake,
  ...
}: {
  imports = [
    flake.nixosModules.audit-shared
    flake.nixosModules.documentation
    flake.nixosModules.mdns
  ];

  # openssh automatically opens its port
  services.openssh.enable = true;
  services.openssh.startWhenNeeded = true; # socket-activated daemon
  services.openssh.extraConfig = ''
    AcceptEnv COLORTERM
  '';

  # Don't restart the running per-connection sshd instance during activation.
  # These hosts are deployed remotely over SSH; restarting sshd@<connid> mid
  # `switch-to-configuration` would kill the deploy's own session before it
  # finishes, aborting activation with units left half-stopped (e.g. avahi).
  # Existing sessions keep the old sshd until they disconnect; new connections
  # pick up the new binary via the socket. See the openssh bump deploy race.
  systemd.services."sshd@".restartIfChanged = false;

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

  # Build only the locales we actually use instead of all ~350 (~220 MB of
  # glibc-locales). These are headless en_US servers; C.UTF-8 is kept because
  # some software expects it.
  i18n.supportedLocales = [
    "en_US.UTF-8/UTF-8"
    "C.UTF-8/UTF-8"
  ];

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
