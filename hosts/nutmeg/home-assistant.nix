{
  config,
  synologyMount,
  utils,
  ...
}: let
  backups = "/var/lib/home-assistant/backups";
  automount = "${utils.escapeSystemdPath backups}.automount";
in {
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

  # 8123 web UI; 21063/21064 HomeKit bridge; 5580 an integration's listener.
  #
  # 5353 is UDP-only (mDNS), so it is listed under UDP alone; a TCP entry for
  # it could never match. It stays declared here even though services.avahi.openFirewall (modules/nixos/mdns.nix) opens
  # the same port: HA does its own mDNS discovery, and that shouldn't quietly
  # break the day avahi gets disabled on this host. Duplicate allowedUDPPorts
  # entries merge to one nftables rule, so the overlap costs nothing.
  networking.firewall.allowedTCPPorts = [
    8123
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
      # rslave carries the backups automount (below) into the container, and
      # with it each NAS mount and idle unmount as they happen on the host.
      # Binding the backups path on its own would instead trigger the mount
      # and bind the NFS mount itself; its first idle unmount would then leave
      # HA writing to the local directory underneath.
      "${config.users.users.homeassistant.home}:/config:rslave"
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

  # HA's automatic backups (~160M each) go straight to the NAS, where HA
  # manages its own retention.
  #
  # HA must never depend on the .mount: synologyMount idle-unmounts after
  # 5 minutes, and a Requires=/RequiresMountsFor= edge on the mount turns that
  # unmount into a clean stop of HA (and fails HA's start at boot whenever the
  # NAS isn't reachable yet). It orders after the .automount instead, which
  # stays up and never stops anything, so that the container's /config bind
  # captures the automount rather than the bare local directory underneath it.
  # With the NAS down, a backup fails after the mount timeout and HA keeps
  # running.
  fileSystems.${backups} = synologyMount "/volume1/app-servarr/home-assistant/backups" {};
  systemd.services.podman-homeassistant = {
    wants = [automount];
    after = [automount];
  };
}
