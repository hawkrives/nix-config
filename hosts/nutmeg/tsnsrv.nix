{ config, ... }:
{
  # Tailscale OAuth client secret (scoped to tag:tsnsrv), used by tsnsrv to mint
  # its own node keys. tsnsrv reads it through systemd LoadCredential as root,
  # so the root-owned 0400 agenix default is all it needs.
  #
  # Keep it in ragenix rather than a file placed on the host: this grants the
  # ability to mint tailnet nodes, and anything outside agenix ends up
  # world-readable to every local user here, `techcyte` (who has ssh access)
  # included. Same arrangement as tuckles. See secrets/secrets.nix.
  age.secrets.tsnsrv-authkey-nutmeg.file = ../../secrets/tsnsrv-authkey-nutmeg.age;

  services.tsnsrv = {
    enable = true;

    defaults = {
      authKeyPath = config.age.secrets.tsnsrv-authkey-nutmeg.path;
      tags = [ "tag:tsnsrv-nutmeg" ];
      ephemeral = true;
      # tsnetVerbose = true;

      urlParts.host = "localhost";
    };
  };
}
