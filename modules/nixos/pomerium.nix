{...}: {
  services.pomerium = {
    enable = true;
    settings = {
      authenticate_service_url = "https://auth.hawken.is";
      routes = [
        {
          from = "https://verify.localhost.pomerium.io";
          to = "http://verify:8000";
          policy = [
            {
              allow."or" = [
                {email.is = "user@example.com";}
              ];
            }
          ];
        }
      ];
    };
    secretsFile = "/var/lib/secrets/pomerium";
    # ^ secretsFile contains the following settings:
    # <nil>
  };
}
