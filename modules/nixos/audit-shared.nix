{...}: {
  # TODO: can we enable this?
  # imports = [<nixpkgs/nixos/modules/profiles/hardened.nix>];

  security.auditd.enable = true;
  security.audit.enable = true;
  security.audit.rules = [
    "-a exit,always -F arch=b64 -S execve"
  ];

  # Don't fsync audit.log on every batch of records. auditd's flush is
  # record-count based (no time knob), so "none" hands writeback to the kernel,
  # which batches dirty pages to disk within ~dirty_expire_centisecs (~30s here).
  # This removes the per-record fsync -> ext4 journal commit that dominated disk
  # writes; it does not reduce the log's data volume (that's the execve rule).
  # Tradeoff: a crash can lose up to the last writeback window of audit records.
  security.auditd.settings = {
    flush = "none";
  };

  services.logrotate.settings = {
    header = {};

    "/var/log/audit/audit.log" = {
      dateext = true;
      dateformat = ".%Y-%m-%dT%H:%M:%S";
      compress = true;

      frequency = "daily";
      rotate = 3;
      size = "1G";

      # compresscmd /usr/local/bin/zstd
      # uncompresscmd /usr/local/bin/unzstd
      # compressoptions -9 --long -T0
      # compressext .zst
    };
  };
}
