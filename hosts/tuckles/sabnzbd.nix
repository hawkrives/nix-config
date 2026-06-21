{ ... }:
{
  services.sabnzbd = {
    enable = true;
    # Use the new settings-based interface. configFile = null silences the
    # `configFile is deprecated` warning (it otherwise defaults to the legacy
    # path because this host's stateVersion is < 26.05).
    configFile = null;
    # Keep the runtime ini writable so the web UI and the seeded config
    # (servers/categories, migrated from the old install) persist; the module
    # merges the declarative `settings` below in on each start, taking
    # precedence, while preserving everything else in the ini.
    allowConfigWrite = true;
    settings.misc = {
      host = "0.0.0.0";
      port = 6000;
      host_whitelist = "sabnzbd,tuckles,sabnzbd.vaquita-woodpecker.ts.net,tuckles.vaquita-woodpecker.ts.net";
    };
  };

  # SAB listens on 6000 (enforced via settings.misc.port above). Open it on the LAN.
  networking.firewall.allowedTCPPorts = [ 6000 ];

  systemd.tmpfiles.rules = [
    "d /var/lib/sabnzbd/incomplete 0770 sabnzbd sabnzbd -"
    "d /var/lib/sabnzbd/complete 0770 sabnzbd sabnzbd -"
  ];
}
