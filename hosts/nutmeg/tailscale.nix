{config, ...}: {
  services.tailscale = {
    enable = true;
    openFirewall = true; # allow the Tailscale UDP port through the firewall
    useRoutingFeatures = "both";
    permitCertUid = "nginx";
    extraUpFlags = ["--accept-dns=false" "--advertise-exit-node"];
  };

  networking.firewall.trustedInterfaces = [config.services.tailscale.interfaceName];
}
