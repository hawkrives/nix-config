{ config, ... }:
{
  # VPN namespace bound to the Mullvad WireGuard config; kill-switch is implicit
  # (only the wg interface has egress). WebUI is forwarded out to the LAN.
  vpnNamespaces.mullvad = {
    enable = true;
    wireguardConfigFile = config.age.secrets.wg-mullvad-tuckles.path;
    accessibleFrom = [
      "192.168.1.0/24"
      "127.0.0.1"
    ];
    portMappings = [ { from = 6001; to = 6001; } ];
  };

  services.qbittorrent = {
    enable = true;
    webuiPort = 6001;
  };

  systemd.services.qbittorrent.vpnConfinement = {
    enable = true;
    vpnNamespace = "mullvad";
  };

  networking.firewall.allowedTCPPorts = [ 6001 ];
}
