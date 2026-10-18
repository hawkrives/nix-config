{config, ...}: let
  # vpn-confinement derives both the namespace unit and its interface names from
  # this string: the bridge is <ns>-br and its host-side port veth-<ns>-br. The
  # avahi denyInterfaces below depends on that, so keep them deriving from one
  # source rather than three literals that can drift apart.
  ns = "airvpn";
in {
  # VPN namespace bound to the AirVPN WireGuard config; kill-switch is implicit
  # (only the wg interface has egress). WebUI is forwarded out to the LAN.
  vpnNamespaces.${ns} = {
    enable = true;
    wireguardConfigFile = config.age.secrets.wg-airvpn-tuckles.path;
    accessibleFrom = [
      "192.168.1.0/24" # LAN (where the *arr on nutmeg reach the WebUI)
      "100.64.0.0/10" # Tailscale CGNAT range (remote admin of the WebUI)
      "127.0.0.1"
    ];
    portMappings = [
      {
        from = 6001;
        to = 6001;
      }
      {
        # slskd web UI (slskd.nix) shares this namespace; expose its port to the LAN.
        from = 5030;
        to = 5030;
      }
      {
        # bitmagnet web UI (bitmagnet.nix). The mapping is what opens 3333 on the
        # netns side of the veth, so the localhost forwarder for tsnsrv can reach
        # it. Its DNAT'd traffic is forwarded rather than delivered locally, so the
        # host firewall doesn't gate it: the UI is reachable on the LAN too.
        from = 3333;
        to = 3333;
      }
    ];
  };

  # Keep avahi off the VPN bridge. Two reasons: publishing this host's LAN
  # <hostname>.local on an AirVPN bridge is wrong on its face, and avahi binding
  # BOTH a bridge and its own member port is a known self-conflict shape --
  # suspected contributor to the 2026-08-26 rename that left tuckles publishing
  # tuckles-3.local and broke every .local deploy. Nothing inside the netns uses
  # mDNS (qBittorrent/slskd are reached by IP at 192.168.15.1), so this is free.
  # NOTE: this is a blocklist -- a future netns or podman bridge would need
  # adding here too. slskd.nix also names this namespace literally.
  services.avahi.denyInterfaces = [
    "${ns}-br"
    "veth-${ns}-br"
  ];

  services.qbittorrent = {
    enable = true;
    webuiPort = 6001;
  };

  # Same shared-gid reasoning as sabnzbd / the *arr: qB moves completed torrents
  # to NFS save paths under /mnt/{shows,movies}. Join "users" (gid 100) so it can
  # write there with mapping off, and UMask 0007 keeps files group-accessible so
  # the *arr can import and Plex can read them.
  users.users.qbittorrent.extraGroups = ["users"];
  systemd.services.qbittorrent.serviceConfig.UMask = "0007";

  systemd.services.qbittorrent.vpnConfinement = {
    enable = true;
    vpnNamespace = ns;
  };

  # The wg config secret's content can change (e.g. swapping AirVPN server)
  # without the unit definition changing, so systemd wouldn't restart the
  # namespace on its own. Restart it when the secret changes so the new config
  # actually loads.
  systemd.services.${ns}.restartTriggers = [config.age.secrets.wg-airvpn-tuckles.file];

  # qBittorrent downloads to a local TempPath (Session\TempPath in its seeded
  # config) before moving completed files to the per-category NFS save path. But
  # /var/lib/qBittorrent is root-owned and the temp/complete dirs were never
  # created, so qB couldn't write incomplete data and every torrent went to the
  # `error` state with 0 progress. Create them owned by the service user, the
  # same way sabnzbd.nix does for SAB.
  systemd.tmpfiles.rules = [
    "d /var/lib/qBittorrent/incomplete 0755 qbittorrent qbittorrent -"
    "d /var/lib/qBittorrent/complete 0755 qbittorrent qbittorrent -"
  ];

  networking.firewall.allowedTCPPorts = [6001];
}
