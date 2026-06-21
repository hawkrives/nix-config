{ ... }:
{
  services.sabnzbd = {
    enable = true;
    # The settings-based interface is the default at this host's stateVersion
    # (>= 26.05), so configFile already defaults to null (no deprecation warning).
    # Keep the runtime ini writable so the web UI and the seeded config
    # (servers/categories, migrated from the old install) persist; the module
    # merges the declarative `settings` below in on each start, taking
    # precedence, while preserving everything else in the ini.
    allowConfigWrite = true;
    settings.misc = {
      host = "::"; # dual-stack: an IPv6 ANY socket also accepts IPv4 (v4-mapped) on Linux,
      port = 6000; # so both 192.168.1.66:6000 and tuckles.local (IPv6) reach SAB
      host_whitelist = "sabnzbd,tuckles,tuckles.local,sabnzbd.vaquita-woodpecker.ts.net,tuckles.vaquita-woodpecker.ts.net";
    };
  };

  # SAB listens on 6000 (enforced via settings.misc.port above). Open it on the LAN.
  networking.firewall.allowedTCPPorts = [ 6000 ];

  systemd.tmpfiles.rules = [
    "d /var/lib/sabnzbd/incomplete 0770 sabnzbd sabnzbd -"
    "d /var/lib/sabnzbd/complete 0770 sabnzbd sabnzbd -"
  ];
}
