{...}: {
  services.peertube = {
    enable = true;
    listenWeb = 23357;
    # configureNginx = true;
    localDomain = "nutmeg.local:23357";

    settings = {
      instance.name = "PeerTube Test Server";
    };
  };

  networking.firewall.allowedTCPPorts = [23357];
}
