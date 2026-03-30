{...}: {
  services.tsnsrv = {
    enable = true;

    defaults = {
      # Requires manual setup: place an OAuth client secret (scoped to tag:tsnsrv) at this path
      authKeyPath = "/etc/tsnsrv/authkey";
      tags = ["tag:tsnsrv-nutmeg"];
      ephemeral = true;
      # tsnetVerbose = true;

      urlParts.host = "localhost";
    };
  };
}
