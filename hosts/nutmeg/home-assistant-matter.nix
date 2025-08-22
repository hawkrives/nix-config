{
  config,
  pkgs,
  ...
}: {
  # enable bluetooth for matter
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  environment.systemPackages = [pkgs.bluez];

  # TODO: move to home-manager?
  users.groups.homeassistant-matter = {
    gid = 10011;
  };
  users.users.homeassistant-matter = {
    uid = 10011;
    group = "homeassistant-matter";
    home = "/var/lib/home-assistant-matter";
    isNormalUser = true;
  };

  virtualisation.oci-containers.containers.homeassistant-matter = {
    image = "ghcr.io/home-assistant-libs/python-matter-server:stable";
    autoStart = true;
    user = "${toString config.users.users.homeassistant-matter.uid}:${toString config.users.groups.homeassistant-matter.gid}";
    volumes = [
      "${config.users.users.homeassistant-matter.home}:/data"
      "/run/dbus:/run/dbus:ro"
    ];
    labels = {
      "io.containers.autoupdate" = "registry";
    };
    environment.TZ = "America/New_York";
    extraOptions = [
      "--pull=newer"
      "--network=host"
      "--security-opt=apparmor=unconfined"
    ];
  };
}
