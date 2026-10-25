# restic from the NAS: what lives here, into the same two repositories nutmeg
# backs up to (hosts/nutmeg/restic.nix), as host "potato-bunny", so each host's
# snapshots and retention stay separate within them.
#
#   nas      /volume1/app-backup/restic/nutmeg, a local path here (nutmeg
#            reaches the same repo over SFTP as hawken, so this runs as
#            hawken too and the repo's files keep one owner)
#   offsite  rsync.net, over SFTP with nutmeg's restic key
#
# Today that is paperless's nightly export (paperless.nix, 01:30): the export
# rather than the data dir, because the metadata lives in PostgreSQL and only
# the export carries both. nutmeg's weekly `check --read-data` of both repos
# covers these snapshots too.
{
  config,
  lib,
  pkgs,
  ...
}: let
  paths = ["/volume1/app-servarr/paperless/export"];
  pruneOpts = [
    "--keep-daily 14"
    "--keep-weekly 8"
    "--keep-monthly 24"
    "--keep-yearly 3"
  ];
  home = "/var/services/homes/hawken";

  knownHosts = pkgs.writeText "restic-known-hosts" ''
    de3044.rsync.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIObQN4P/deJ/k4P4kXh6a9K4Q89qdyywYetp9h3nwfPo
  '';
  sftpCommand = lib.concatStringsSep " " [
    "${pkgs.openssh}/bin/ssh"
    "-i ${config.age.secrets.restic-ssh-key.path}"
    "-o IdentitiesOnly=yes"
    "-o UserKnownHostsFile=${knownHosts}"
    "-o StrictHostKeyChecking=yes"
    "de3044@de3044.rsync.net -s sftp"
  ];

  # Back up, then apply this host's retention. Same policy as nutmeg's.
  job = name: repository:
    pkgs.writeShellScript "restic-${name}" ''
      set -euo pipefail
      export RESTIC_REPOSITORY=${lib.escapeShellArg repository}
      export RESTIC_PASSWORD_FILE=${config.age.secrets.restic-password.path}
      export HOME=${home}
      r() { ${pkgs.restic}/bin/restic -o sftp.command=${lib.escapeShellArg sftpCommand} "$@"; }
      r backup --host potato-bunny ${lib.escapeShellArgs paths}
      r forget --host potato-bunny --prune ${lib.concatStringsSep " " pruneOpts}
      # The heartbeat: Uptime Kuma alerts if this stops arriving (uptime-kuma.nix).
      ${pkgs.curl}/bin/curl -fsS --max-time 20 -o /dev/null "http://127.0.0.1:3010/api/push/restic-pb-${name}?status=up&msg=OK" ||
        echo "restic-${name}: heartbeat push failed" >&2
    '';

  unit = name: repository: calendar: {
    "restic-pb-${name}.service" = {
      wantedBy = [];
      text = ''
        [Unit]
        Description=restic: back up this NAS to ${name}
        OnFailure=notify-failure@%n.service
        After=paperless-exporter.service network-online.target
        RequiresMountsFor=/volume1

        [Service]
        Type=oneshot
        User=hawken
        ExecStart=${job name repository}
        Nice=10
        IOSchedulingClass=idle
      '';
    };
    "restic-pb-${name}.timer" = {
      wantedBy = ["timers.target"];
      text = ''
        [Unit]
        Description=restic: back up this NAS to ${name}, nightly

        [Timer]
        OnCalendar=${calendar}
        Persistent=true
      '';
    };
  };
in {
  age.secrets.restic-password = {
    file = ../../secrets/restic-password-nutmeg.age;
    owner = "hawken";
  };
  age.secrets.restic-ssh-key = {
    file = ../../secrets/restic-ssh-key-nutmeg.age;
    owner = "hawken";
  };

  uptimeKuma.localHeartbeats = [
    {
      unit = "restic-pb-nas.service";
      interval = 90000; # daily, no jitter
    }
    {
      unit = "restic-pb-offsite.service";
      interval = 90000;
    }
  ];

  # After the 01:30 export; before nutmeg's own runs at 03:00 and 04:00.
  systemd.units =
    unit "nas" "/volume1/app-backup/restic/nutmeg" "*-*-* 02:00"
    // unit "offsite" "sftp:de3044@de3044.rsync.net:restic/nutmeg" "*-*-* 02:30";
}
