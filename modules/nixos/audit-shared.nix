{...}: {
  # TODO: can we enable this?
  # imports = [<nixpkgs/nixos/modules/profiles/hardened.nix>];

  security.auditd.enable = true;
  security.audit.enable = true;
  security.audit.rules = [
    "-a exit,always -F arch=b64 -S execve"
  ];

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
