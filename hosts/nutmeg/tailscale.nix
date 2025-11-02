{config, ...}: {
  services.tailscale = {
    enable = true;
    openFirewall = true; # allow the Tailscale UDP port through the firewall
    useRoutingFeatures = "both";
    permitCertUid = "nginx";
    extraUpFlags = ["--accept-dns=false" "--advertise-exit-node"];
  };

  # always allow traffic from your Tailscale network
  networking.firewall.trustedInterfaces = [config.services.tailscale.interfaceName];

  environment.systemPackages = [
    # tsnsrv.default
  ];
}
