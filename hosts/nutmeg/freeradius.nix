{pkgs, ...}: let
  accessPointIp = "192.168.1.1";
  sharedSecret = "changeme"; # insecure value is OK because we don't expose this server to the internet

  clientsConfig = ''
    client ap {
      ipaddr = ${accessPointIp}
      secret = "${sharedSecret}"
      require_message_authenticator = no
      shortname = ap
    }
  '';

  usersConfig = ''
    ## Test Users for E2E Testing ##

    # Blocklisted Users for Failure Testing
    baduser1  Auth-Type := Reject
      Reply-Message = "Authentication rejected"

    # These credentials should ACCEPT and allow connection
    # User format: username  Auth-Type := Local, User-Password == "password"
    testuser1  Password.Cleartext := "testpass1"
      Fall-Through = yes

    testuser2  Password.Cleartext := "testpass2"
      Fall-Through = yes

    DEFAULT
      Reply-Message := "Hello %{User-Name}"
  '';

  customRaddb = pkgs.writeTextDir "freeradius-config" {
    "clients.conf" = clientsConfig;
    "users" = usersConfig;
  };
in {
  services.freeradius = {
    enable = true;
    configDir = customRaddb;
  };
}
