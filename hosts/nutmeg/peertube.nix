{pkgs, ...}: {
  environment.systemPackages = [pkgs.tailscale-nginx-auth];
  services.peertube = {
    enable = false;
    listenWeb = 23357;
    # configureNginx = true;
    localDomain = "nutmeg.local:23357";

    redis.createLocally = true;
    database.createLocally = true;

    secrets.secretsFile = "/etc/peertube/secret";

    settings = {
      instance.name = "PeerTube Test Server";
    };
  };

  # services.tsbridge.services.peertube = {
  #   backend_addr =
  # };

  # TODO: replace with age
  environment.etc."peertube/secret".text = "8f8fed4ded8dfa7c857e962e6855ae248ebc38ef7d3cf164f8561eed845309f7";

  networking.firewall.allowedTCPPorts = [23357];
}
