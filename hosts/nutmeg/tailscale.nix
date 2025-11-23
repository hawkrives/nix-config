{
  config,
  perSystem,
  pkgs,
  ...
}: let
  tailscalePackage = perSystem.nixpkgs-unstable.tailscale;

  tailscaleServeConfig = {
    version = "0.0.1"; # The "Service" configuration file format version. Must be "0.0.1".
    services = {
      # "svc:<service-name>" is the name of the service (for example, `svc:web-server` or `svc:printer`)
      # Each service can contain one or more endpoint mappings
      # mapping: "<protocol>:<port|port-range>" = "<local-target>"

      # example:
      # "svc:other".endpoints."tcp:443" = "http://localhost:8080";
      "svc:adguard".endpoints."tcp:443" = "http://localhost:5380";
      "svc:plex".endpoints."tcp:443" = "http://localhost:32400";
      "svc:peertube".endpoints."tcp:443" = "http://localhost:23357";
      "svc:paperless".endpoints."tcp:443" = "http://localhost:28981";
      "svc:techcyte-chat".endpoints."tcp:443" = "http://techcyte-chat.localhost:80";
      "svc:homeassistant".endpoints."tcp:443" = "http://localhost:8123";
    };
  };

  tailscaleServeConfigFilename = "tailscale-serve.json";
  tailscaleServeConfigPath = "/etc/${tailscaleServeConfigFilename}";

  # 2. Generate the "tailscale serve advertise" commands from the data
  advertiseCommands = pkgs.lib.strings.concatStringsSep "\n" (
    map
    (serviceName: "${tailscalePackage}/bin/tailscale serve advertise ${serviceName}")
    (builtins.attrNames tailscaleServeConfig.services) # Gets ["svc:adguard", "svc:my-app", ...]
  );

  # 3. Create a script that systemd will run
  updateScript = pkgs.writeScriptBin "tailscale-serve-update" ''
    #!${pkgs.runtimeShell}
    set -euo pipefail

    echo "Applying Tailscale serve config from ${tailscaleServeConfigPath}..."
    ${tailscalePackage}/bin/tailscale serve set-config --all ${tailscaleServeConfigPath}

    echo "Advertising services..."
    ${advertiseCommands}

    echo "Tailscale serve configuration applied."
  '';
in {
  services.tailscale = {
    enable = true;
    package = tailscalePackage;
    openFirewall = true; # allow the Tailscale UDP port through the firewall
    useRoutingFeatures = "both";
    permitCertUid = "nginx";
    extraUpFlags = ["--accept-dns=false" "--advertise-exit-node"];
  };

  networking.firewall.trustedInterfaces = [config.services.tailscale.interfaceName];

  # generate tailscale-serve config file
  # environment.etc.${tailscaleServeConfigFilename}.text = builtins.toJSON tailscaleServeConfig;

  # automatically apply tailscale-serve config whenever it changes
  # systemd.services.tailscale-serve-apply = {
  #   description = "Apply Tailscale serve configuration";

  #   # This service is a one-shot script
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${updateScript}/bin/tailscale-serve-update";
  #   };

  #   # Run after tailscale is up and the network is online
  #   after = ["tailscale.service" "network-online.target"];
  #   wants = ["network-online.target"];

  #   # Run this service on boot
  #   wantedBy = ["multi-user.target"];
  # };
}
