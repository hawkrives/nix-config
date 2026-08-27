{ pkgs, ... }:
{
  services.sabnzbd = {
    # SABnzbd gates archive extraction on a hardcoded regex in filesystem.py:
    #
    #   SEVENZIP_RE = re.compile(r"\.(zip|7z)$", re.I)
    #
    # Only files matching it are handed to 7z, so a job whose payload is a plain
    # `.tar` is never even offered to the unpacker — SAB moves the tar to the
    # completed dir as-is and Lidarr parks the item on "Found archive file, might
    # need to be extracted". Several usenet music groups (ENRiCH, ENViED, SDR,
    # C4, QUAVER, MyMom, ...) now post exactly that, so the *arr queues fill with
    # stuck imports. There is no setting for this; `enable_7zip` is already on
    # and the bundled p7zip extracts these tars fine with the very flags SAB
    # passes (`7z x -y -aou -ssc -p -o<dest>`) — the regex is the only blocker.
    #
    # So teach the regex about `.tar`. 7z handles a tar in a single pass, and
    # everything downstream (deleting the original, unpack_info, retries, the
    # recursive unpack_magic re-scan) is the same code path zip/7z already take.
    # --replace-fail means a nixpkgs bump that reworks this line fails the build
    # loudly instead of silently dropping the fix.
    package = pkgs.sabnzbd.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace sabnzbd/filesystem.py \
          --replace-fail 'r"\.(zip|7z)$"' 'r"\.(zip|7z|tar)$"'
      '';
    });

    enable = true;
    # The settings-based interface is the default at this host's stateVersion
    # (>= 26.05), so configFile already defaults to null (no deprecation warning).
    # Keep the runtime ini writable so the web UI and the seeded config
    # (servers/categories, migrated from the old install) persist; the module
    # merges the declarative `settings` below in on each start, taking
    # precedence, while preserving everything else in the ini.
    allowConfigWrite = true;

    # Run SAB with primary group "users" (gid 100), the group the *arr import
    # through on the NFS media shares. SAB assembles each job in its local
    # incomplete dir and moves it to the category folder on NFS; the moved
    # folder takes SAB's *primary* gid, not the setgid parent's group, so with
    # the default "sabnzbd" group every download landed group-994 (sabnzbd) and
    # Lidarr (gid 100) was locked out as "other". Primary group 100 makes
    # everything SAB creates group-users regardless of setgid behaviour. (Safe:
    # sabnzbd.ini is 0600 owner-only, so group-users doesn't expose the API key.)
    group = "users";

    settings.misc = {
      host = "0.0.0.0";
      port = 6000;
      host_whitelist = "sabnzbd,tuckles,tuckles.local,sabnzbd.vaquita-woodpecker.ts.net,tuckles.vaquita-woodpecker.ts.net,sab.vaquita-woodpecker.ts.net";
      # SAB's daemon mode (it's started with `-d`) deliberately clobbers the
      # process umask: SABnzbd.py does `os.umask(prev and 0o77)`, forcing 0077
      # whenever the inherited umask is non-zero — so the systemd UMask below is
      # INERT for the files SAB creates and every download came out mode 0700,
      # unreadable to the "users" group the *arr import through. This explicit
      # `permissions` makes SAB chmod completed files/dirs itself, bypassing the
      # daemon umask: dirs 0770, files rw for owner+group. Combined with the
      # group = "users" above, the *arr (gid 100) can read+import. (SAB's chmod
      # strips the setgid bit, which is why group ownership can't be left to
      # setgid inheritance and is pinned via the primary group instead.)
      permissions = "0770";
    };
  };

  systemd.services.sabnzbd.serviceConfig.UMask = "0007";

  # SAB listens on 6000 (enforced via settings.misc.port above). Open it on the LAN.
  networking.firewall.allowedTCPPorts = [ 6000 ];

  # Local staging dirs, owned by SAB's new primary group so assembled files are
  # group-users before the move to NFS.
  systemd.tmpfiles.rules = [
    "d /var/lib/sabnzbd/incomplete 0770 sabnzbd users -"
    "d /var/lib/sabnzbd/complete 0770 sabnzbd users -"
  ];
}
