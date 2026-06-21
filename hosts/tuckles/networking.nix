{ config, ... }:
{
  # DHCP via systemd-networkd (configuration.nix sets useNetworkd). The router
  # pins this host to 192.168.1.66 via a static DHCP reservation on its MAC.
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "en*";
    networkConfig.DHCP = "ipv4";
    linkConfig.RequiredForOnline = "routable";
  };

  # Tailscale (LAN + tailnet).
  services.tailscale = {
    enable = true;
    openFirewall = true;
    authKeyFile = config.age.secrets.tailscale-authkey-tuckles.path;
  };
  networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
}
