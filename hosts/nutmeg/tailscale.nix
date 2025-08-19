{...}: {
  services.tailscale = {
    enable = true;
    openFirewall = true; # allow the Tailscale UDP port through the firewall
    useRoutingFeatures = "both";
    permitCertUid = "nginx";
    extraUpFlags = [
      "--accept-dns=false"
      "--advertise-exit-node"
    ];
  };

  # always allow traffic from your Tailscale network
  networking.firewall.trustedInterfaces = ["tailscale0"];

  environment.systemPackages = [
    # tsnsrv.default
  ];
}
