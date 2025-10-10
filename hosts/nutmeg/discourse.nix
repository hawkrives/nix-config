{...}: {
  networking.firewall.allowedTCPPorts = [80];
  services.discourse = {
    enable = true;
    hostname = "nutmeg.local";
    enableACME = false;
    backendSettings = {
      max_reqs_per_ip_per_minute = 30000;
      max_reqs_per_ip_per_10_seconds = 6000;
      max_asset_reqs_per_ip_per_10_seconds = 25000;

      ### rate limits apply to all sites
      max_user_api_reqs_per_minute = 2000;
      max_user_api_reqs_per_day = 288000;
      max_admin_api_reqs_per_key_per_minute = 60000;
      # max_reqs_per_ip_per_minute = 200;
      # max_reqs_per_ip_per_10_seconds = 50;
      # applies to asset type routes (avatars/css and so on)
      # max_asset_reqs_per_ip_per_10_seconds = 200;
      # global rate limiter will simply warn if the limit is exceeded, can be warn+block, warn, block or none
      max_reqs_per_ip_mode = "warn";
      # bypass rate limiting any IP resolved as a private IP
      max_reqs_rate_limit_on_private = false;
    };
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
