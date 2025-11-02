{
  config,
  perSystem,
  ...
}: {
  services.tailscale = {
    enable = true;
    package = perSystem.nixpkgs-unstable.tailscale;
    openFirewall = true; # allow the Tailscale UDP port through the firewall
    useRoutingFeatures = "both";
    permitCertUid = "nginx";
    extraUpFlags = ["--accept-dns=false" "--advertise-exit-node"];
  };

  # always allow traffic from your Tailscale network
  networking.firewall.trustedInterfaces = [config.services.tailscale.interfaceName];

  environment.etc."tailscale-serve.json" = builtins.toJSON {
    version = "0.0.1"; # The Service configuration file format version. Must be "0.0.1".
    services = {
      # "svc:<service-name>" is the name of the service (for example, `svc:web-server` or `svc:printer`)
      "svc:adguard" = {
        # Can contain one or more endpoint mappings
        "endpoints" = {
          # "<protocol>:<port|port-range>" = "<local-target>"; # Maps incoming traffic to a local target
          "tcp:443" = "http://localhost:5380";
        };
      };
    };
  };
}
