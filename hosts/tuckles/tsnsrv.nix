{ config, ... }:
{
  services.tsnsrv = {
    enable = true;

    defaults = {
      # Manual setup (mirrors nutmeg): place an OAuth client secret scoped to
      # tag:tsnsrv-tuckles at this path (mode 0400, owned by the tsnsrv user).
      authKeyPath = "/etc/tsnsrv/authkey";
      tags = [ "tag:tsnsrv-tuckles" ];
      ephemeral = true;
      urlParts.host = "localhost";
    };

    # qui at https://qui.vaquita-woodpecker.ts.net -> localhost:7476
    services.qui.urlParts.port = config.services.qui.settings.port;
  };
}
