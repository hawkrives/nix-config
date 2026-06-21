{ config, ... }:
{
  # DHCP via systemd-networkd (configuration.nix sets useNetworkd). The router
  # pins this host to 192.168.1.66 via a static DHCP reservation on its MAC.
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "en*";
    networkConfig.DHCP = "ipv4";
    linkConfig.RequiredForOnline = "routable";
  };

  # Tailscale (LAN + tailnet). The auth key is an OAuth client secret, so the
  # node must advertise the tags the client is scoped to.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    authKeyFile = config.age.secrets.tailscale-authkey-tuckles.path;
    extraUpFlags = [ "--advertise-tags=tag:container,tag:servarr" ];
  };
  networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
}
