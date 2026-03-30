{config, ...}: {
  # it's OK to open :53, because the router won't allow unexpected connections
  # from the internet to the machines
  networking.firewall.allowedTCPPorts = [53];
  networking.firewall.allowedUDPPorts = [53];

  services.adguardhome = {
    enable = true;
    mutableSettings = true;
    openFirewall = true;
    port = 5380;

    # settings.http.address = "0.0.0.0:${toString port}";
    settings.dns.bind_hosts = ["0.0.0.0"];
  };

  services.tsnsrv.services.ag.toURL = "http://localhost:${toString config.services.adguardhome.port}";
}
