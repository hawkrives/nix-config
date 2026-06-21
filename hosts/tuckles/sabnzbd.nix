{ ... }:
{
  services.sabnzbd = {
    enable = true;
    # configFile defaults to /var/lib/sabnzbd/sabnzbd.ini; the runtime ini is
    # seeded once from the migrated old config (not managed declaratively).
  };

  # SAB listens on 6000 (set in the seeded ini). Open it on the LAN.
  networking.firewall.allowedTCPPorts = [ 6000 ];

  systemd.tmpfiles.rules = [
    "d /var/lib/sabnzbd/incomplete 0770 sabnzbd sabnzbd -"
    "d /var/lib/sabnzbd/complete 0770 sabnzbd sabnzbd -"
  ];
}
