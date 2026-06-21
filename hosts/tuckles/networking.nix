{ config, ... }:
{
  # Static LAN address via systemd-networkd (configuration.nix sets useNetworkd).
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "en*";
    address = [ "192.168.1.195/24" ];
    routes = [ { Gateway = "192.168.1.1"; } ];
    networkConfig.DNS = "192.168.1.194";
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
