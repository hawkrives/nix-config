{pkgs, ...}: {
  services.freeradius = {
    enable = true;
    debug = true;
    # Define a user for the client to connect with
    configDir = pkgs.writeTextDir "users" ''
      testuser Cleartext-Password := "testpassword"
    '';
  };
}
