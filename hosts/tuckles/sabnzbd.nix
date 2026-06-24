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
      host = "0.0.0.0";
      port = 6000;
      host_whitelist = "sabnzbd,tuckles,tuckles.local,sabnzbd.vaquita-woodpecker.ts.net,tuckles.vaquita-woodpecker.ts.net,sab.vaquita-woodpecker.ts.net";
    };
  };

  # SAB writes completed downloads into the NFS media shares (/mnt/shows,
  # /mnt/movies) the *arr import from. Those trees grant write via the "users"
  # group (gid 100); with NFS user-mapping off SAB writes as its own uid, so it
  # must join "users" or it lands in "other" and can't write the 0770 shares.
  # UMask 0007 keeps what it creates group read+writable so the *arr can
  # hardlink/import and Plex can read it — the default 0022 left staging files
  # non-group-writable (and the old 0600/0700 leftovers came from this gap).
  users.users.sabnzbd.extraGroups = [ "users" ];
  systemd.services.sabnzbd.serviceConfig.UMask = "0007";

  # SAB listens on 6000 (enforced via settings.misc.port above). Open it on the LAN.
  networking.firewall.allowedTCPPorts = [ 6000 ];

  systemd.tmpfiles.rules = [
    "d /var/lib/sabnzbd/incomplete 0770 sabnzbd sabnzbd -"
    "d /var/lib/sabnzbd/complete 0770 sabnzbd sabnzbd -"
  ];
}
