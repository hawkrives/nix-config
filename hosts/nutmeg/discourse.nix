{...}: {
  networking.firewall.allowedTCPPorts = [80];
  services.discourse = {
    enable = true;
    hostname = "nutmeg.local";
    enableACME = false;
    backendSettings = {};
    siteSettings = {
      email.disable_emails = "yes";
    };
    admin = {
      email = "admin@nutmeg.local";
      fullName = "Admin";
      passwordFile = "/etc/discourse/admin-password.txt";
      username = "admin";
    };
  };
}
