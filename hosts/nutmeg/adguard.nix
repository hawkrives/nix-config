{ config, ... }: {
  # it's OK to open :53, because the router won't allow unexpected connections
  # from the internet to the machines
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  services.adguardhome = {
    enable = true;
    mutableSettings = true;
    openFirewall = true;
    port = 5380;

    settings.dns.bind_hosts = [
      "192.168.1.228"
      "2600:2b00:9b16:6d01::228"
    ];

    # upstream_mode is load_balance, so each query goes to exactly one of the
    # upstreams configured in the web UI. These catch the query when that one
    # fails, instead of handing the client back a SERVFAIL.
    settings.dns.fallback_dns = [
      "1.1.1.1"
      "9.9.9.10"
    ];
  };

  # if AdGuard starts before the static v6 address is configured on the
  # interface, the bind fails and the service won't come up. This lets it bind
  # to the address even if it isn't present yet.
  boot.kernel.sysctl."net.ipv6.ip_nonlocal_bind" = 1;

  services.tsnsrv.services.ag.urlParts.port = config.services.adguardhome.port;
}
