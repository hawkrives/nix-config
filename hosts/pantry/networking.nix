{ config, ... }:
{
  # DHCP via systemd-networkd. Pin a static DHCP reservation on the router for
  # this VM's MAC if you want a stable LAN IP.
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
    # TASK 5: uncomment once secrets/tailscale-authkey-pantry.age exists (Task 4).
    # authKeyFile = config.age.secrets.tailscale-authkey-pantry.path;
    extraUpFlags = [ "--advertise-tags=tag:container" ];
  };
  networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
}
