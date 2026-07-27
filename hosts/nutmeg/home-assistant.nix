{
  config,
  synologyMount,
  ...
}: {
  # Long-lived Home Assistant access token (ragenix). Decrypts to
  # /run/agenix/hass-token (root-owned, 0400) for driving the HA REST/WebSocket
  # API — the *supported* way to edit dashboards, config entries and registries,
  # instead of hand-editing /var/lib/home-assistant/.storage (which can corrupt
  # the store). See docs/home-assistant.md.
  age.secrets.hass-token.file = ../../secrets/hass-token.age;

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

  services.tsnsrv.services.ha.urlParts.port = 8123;

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
    # Deliberately runs as an unprivileged user, WITHOUT NET_ADMIN/NET_RAW.
    #
    # Those caps only buy HA's `bluetooth_auto_recovery`, which manages hci0
    # directly over raw HCI/mgmt sockets. Host bluetoothd already owns the
    # adapter, so granting them gives the adapter two masters. When we made the
    # caps effective (66bb992, 2026-07-19) the BCM20702B0 started emitting
    # "Malformed LE Event: 0x02" and wedged its firmware within 3 days; every
    # HCI command then returned -110 and HA retried ~33k times without ever
    # recovering it. The two prior boots (22 days) had zero such errors.
    #
    # Passive BLE sensors (aranet, ibeacon) do NOT need these caps — they read
    # advertisements through BlueZ over the /run/dbus mount below.
    user = "${toString config.users.users.homeassistant.uid}:${toString config.users.groups.homeassistant.gid}";
    volumes = [
      "${config.users.users.homeassistant.home}:/config"
      # Bind the NAS-backed backups dir EXPLICITLY, even though it already sits
      # under /config via the line above. Podman binds with rprivate
      # propagation, so the parent bind captures whatever is at
      # <home>/backups at container-start time and never sees later host-side
      # (un)mounts. Naming it as its own volume makes podman resolve — and so
      # trigger the automount for — that exact path when the container starts.
      # See the fileSystems entry and unit ordering below.
      "${config.users.users.homeassistant.home}/backups:/config/backups"
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

  # HA's automatic backups are ~160M each and it keeps every one it is told to;
  # 15 dailies had grown to 2.4G on the root SSD. Park them on the NAS.
  fileSystems."/var/lib/home-assistant/backups" =
    synologyMount "/volume1/app-servarr/home-assistant/backups"
      { };

  # Without this the container can win the race at boot and bind an *unmounted*
  # /var/lib/home-assistant/backups, at which point HA happily writes backups to
  # the local dir hidden underneath the mountpoint — a failure that stays
  # invisible until the day you need a restore. RequiresMountsFor pulls in the
  # automount unit and orders us after it.
  systemd.services.podman-homeassistant.unitConfig.RequiresMountsFor =
    "/var/lib/home-assistant/backups";
}
