{ config, ... }:
{
  # Tailscale OAuth client secret (scoped to tag:tsnsrv), used by tsnsrv to mint
  # its own node keys. tsnsrv reads it through systemd LoadCredential as root,
  # so the root-owned 0400 agenix default is all it needs.
  #
  # This was a hand-placed /etc/tsnsrv/authkey until 2026-08-29 — the last
  # imperative secret on this host, and it was mode 0644: an OAuth client secret
  # readable by every local user, `techcyte` (who has ssh access here) included.
  # tuckles already did this properly; nutmeg now matches. See secrets/secrets.nix.
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
