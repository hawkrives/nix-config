{...}: let
  port = 5380;
in {
  # it's OK to open :53, because the router won't allow unexpected connections
  # from the internet to the machines
  networking.firewall.allowedTCPPorts = [
    53
    port
  ];
  networking.firewall.allowedUDPPorts = [
    53
    port
  ];

  services.adguardhome = {
    enable = true;
    mutableSettings = true;
    port = port;
    # settings.http.address = "0.0.0.0:${toString port}";
    settings.dns.bind_hosts = ["0.0.0.0"];
  };
}
