{config, ...}: {
  # TODO: move to home-manager?
  users.groups.homeassistant = {
    gid = 10010;
  };
  users.users.homeassistant = {
    uid = 10010;
    group = "homeassistant";
    home = "/var/lib/home-assistant";
    isNormalUser = true;
  };

  networking.firewall.allowedTCPPorts = [
    8123
    5353
    21063
    21064
    5580
  ];
  networking.firewall.allowedUDPPorts = [
    5353
    21063
    21064
    5580
  ];

  virtualisation.oci-containers.containers.homeassistant = {
    image = "ghcr.io/home-assistant/home-assistant:stable";
    autoStart = true;
    user = "${toString config.users.users.homeassistant.uid}:${toString config.users.groups.homeassistant.gid}";
    volumes = [
      "${config.users.users.homeassistant.home}:/config"
      "/run/dbus:/run/dbus:ro"
    ];
    labels = {
      "io.containers.autoupdate" = "registry";
    };
    environment.TZ = "America/New_York";
    extraOptions = [
      "--network=host"
      "--pull=newer"
    ];
  };
}
