{ config, ... }:
{
  # Wired USB-C ethernet, DHCP via systemd-networkd. Pin a DHCP reservation on the
  # router for a stable LAN IP. `en*` matches USB ethernet (enpXsYuZ) too.
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "en*";
    networkConfig.DHCP = "ipv4";
    linkConfig.RequiredForOnline = "routable";
  };

  # Tailscale (LAN + tailnet). Auth key is an OAuth-scoped key; advertise the tag.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    authKeyFile = config.age.secrets.tailscale-authkey-bigpond.path;
    extraUpFlags = [ "--advertise-tags=tag:bigpond" ];
  };
  networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
}
