{...}: {
  services.discourse = {
    enable = true;
    hostname = "nutmeg.local";
    enableACME = false;
    backendSettings = {};
    siteSettings = {
      email.disable_emails = "yes";
    };
  };
}
