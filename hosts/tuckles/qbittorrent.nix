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

  networking.firewall.allowedTCPPorts = [ 6001 ];
}
