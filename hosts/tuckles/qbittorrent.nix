{ config, ... }:
{
  # VPN namespace bound to the Mullvad WireGuard config; kill-switch is implicit
  # (only the wg interface has egress). WebUI is forwarded out to the LAN.
  vpnNamespaces.mullvad = {
    enable = true;
    wireguardConfigFile = config.age.secrets.wg-mullvad-tuckles.path;
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
    ];
  };

  services.qbittorrent = {
    enable = true;
    webuiPort = 6001;
  };

  systemd.services.qbittorrent.vpnConfinement = {
    enable = true;
    vpnNamespace = "mullvad";
  };

  # The wg config secret's content can change (e.g. swapping Mullvad city)
  # without the unit definition changing, so systemd wouldn't restart the
  # namespace on its own. Restart it when the secret changes so the new config
  # actually loads.
  systemd.services.mullvad.restartTriggers = [ config.age.secrets.wg-mullvad-tuckles.file ];

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

  networking.firewall.allowedTCPPorts = [ 6001 ];
}
