# potato-bunny (Synology DS1821+, DSM 7.4) system layer: the root-owned part
# of the NAS this flake manages. Built into .#potato-bunny-system by
# packages/potato-bunny-system and applied by its `activate`, from
# `mise run potato-bunny:ask` and at every boot (DSM Task Scheduler task
# "Mount nix and start daemon"). Everything else on the machine is DSM's.
{
  lib,
  pkgs,
  perSystem,
  ...
}: let
  lix = perSystem.self.lix-dsm;
in {
  imports = [./nix-cache.nix ./mbx-cache.nix ./watch.nix];

  nix.package = lix;
  profileExtra = [pkgs.cacert];

  # /etc/nix is a bind mount of /volume1/nix/etc (set up by the boot task), so
  # this lands on the volume and survives DSM updates.
  #
  # Substituters: cache.nixos.org and nix-community. This store is itself the
  # fleet's cache (nix-cache.nix): other hosts push their signed builds here,
  # which is why their keys are trusted below. DSM's Tailscale runs with a
  # real tailscale0 (the "tailscale tunnel" boot task runs configure-host), so
  # the tailnet works in both directions.
  environment.etc."nix/nix.conf".text = ''
    build-users-group = nixbld
    trusted-users = root hawken
    experimental-features = nix-command flakes
    sandbox = true
    max-jobs = auto
    substituters = https://cache.nixos.org https://nix-community.cachix.org
    trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs= nutmeg:6F0E+NkIvpTI0d4QSvrDb3+LYhrQwXkYjqgI9etpuEw= pantry:eH1y5GJInQcb8pW/gXQq5GiMiszHIjhqpeMgktIDOQA= Techcyte-DGQJV434PF:FDqhahy007nFE2T8Cj5sBu7uacsP5N9V9dbuERDeeSc= potato-bunny:i8Ab1IPNDKp9EWfmFDZIvMm70c+D435UlIsVFhJO3ts= tuckles:QXDvYTGgHgAIo/EzWTn/UcTuKZEP1MqsQsX9/3apQsc=
  '';

  # No socket unit: the daemon listens itself, so `activate` can verify it
  # answers right after a restart. Only systemd-219 directives.
  systemd.units."nix-daemon.service".text = ''
    [Unit]
    Description=Nix Daemon (Lix, patched for DSM)
    RequiresMountsFor=/nix/store /nix/var /etc/nix

    [Service]
    ExecStart=${lix}/bin/nix-daemon --daemon
    Environment=NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    KillMode=process
    LimitNOFILE=1048576
    Restart=on-failure
    RestartSec=2
  '';

  # The installer created nixbld1..32, and DSM dropped them from the group
  # when it rewrote /etc/group.
  users.groups.nixbld.members = map (i: "nixbld${toString i}") (lib.range 1 32);

  homeUsers.hawken.uid = 1027;

  # DSM Task Scheduler tasks (run as root): boot-up ones, and "tailscale
  # update" on a schedule. The one boot task this layer
  # doesn't manage is "Mount nix and start daemon": it is what runs activate,
  # so scripts/deploy-potato-bunny.sh owns it.
  dsm.tasks = let
    notify = {
      notifyOnError = true;
      notifyMail = "hawkrives@fastmail.fm";
    };
  in {
    # 007revad's scripts, from /volume1/bin/007revad: add the drives to DSM's
    # compatibility db, then enable deduplication for them.
    "Synology_HDD_db" =
      notify
      // {
        event = "bootup";
        script = "bash /volume1/bin/007revad/Synology_HDD_db/syno_hdd_db.sh --noupdate --ram --autoupdate=3 --email -S";
      };
    "Synology_enable_Deduplication" =
      notify
      // {
        event = "bootup";
        dependsOn = "Synology_HDD_db";
        script = "bash /volume1/bin/007revad/Synology_enable_Deduplication/syno_enable_dedupe.sh --autoupdate=3 --email --hdd";
      };
    "tailscale tunnel" = {
      event = "bootup";
      script = "/var/packages/Tailscale/target/bin/tailscale configure-host; synosystemctl restart pkgctl-Tailscale.service\n";
    };
    # Passwordless sudo for hawken, which deploys rely on. /etc/sudoers.d
    # doesn't survive DSM updates, so it's rewritten at every boot.
    "add hawken to sudoers" =
      notify
      // {
        event = "bootup";
        script = "#!/bin/sh\nprintf 'hawken ALL=(ALL) NOPASSWD: ALL\\n' > /etc/sudoers.d/hawken\nchmod 0440 /etc/sudoers.d/hawken";
      };
    # synology_hibernation_fixer by AlexFromChaos (MIT, see
    # hdd-hibernation-fixer.LICENSE), from 007revad's fork at 62b2361
    # (cloned in /volume1/bin/007revad/). Stops DSM waking the HDDs: patches
    # scemd/synostoraged in memory and rewrites DSM's cron task configs from
    # the choices its --install baked into g_user_config, which is why this
    # copy differs from the clone's hiber_fixer.py. Logs to
    # /var/log/hibernation_fixer.log. Runs from the store, so it waits for the
    # task that mounts /nix.
    "HDD Hibernation Fixer task" = {
      event = "bootup";
      dependsOn = "Mount nix and start daemon";
      script = "python3 ${./hdd-hibernation-fixer.py} --run";
    };
    "enable nested virtualization" = {
      event = "bootup";
      script = "modprobe -r kvm_amd\nmodprobe kvm_amd nested=1";
    };
    "enable wifi card" = {
      event = "bootup";
      script = "/sbin/modprobe usbserial\n/sbin/modprobe ftdi_sio\n#/sbin/modprobe cdc-acm";
    };
    "tailscale update" = {
      event = "schedule";
      script = "tailscale update --yes";
      schedule = {
        hour = 0;
        minute = 0;
      };
    };
  };

  # DSM packages and feature settings, applied at deploy (not at boot).
  # `enable = false` stops a package and leaves it installed; packages,
  # services and setting keys not listed here are DSM's to manage.
  dsm.packageSources.SynoCommunity = "https://packages.synocommunity.com/";
  dsm.services = {
    container-manager.enable = true;
    tailscale.enable = true;
    syncthing = {
      package = "syncthing"; # from SynoCommunity
      enable = true;
    };
    smb = {
      enable = true;
      settings = {
        workgroup = "POTATOBUNNY";
        smb_min_protocol = 1;
        smb_max_protocol = 3;
        smb_encrypt_transport = 1;
      };
    };
    ssh = {
      enable = true;
      settings.ssh_port = 22;
    };
  };

  # The beszel agent, natively. docs/beszel-synology.md explains each setting
  # (why the LAN hub address, why :sat, the synthetic sensors tree, why NVMe
  # needs CAP_SYS_ADMIN); this unit only carries them.
  #
  # Runs as root, bounded to the capabilities SMART and the sensors need.
  # DATA_DIR is the Docker agent's old data dir: its `fingerprint` is the
  # agent's identity in the hub, so reusing it keeps the same system and its
  # history. TOKEN (the hub's universal registration token) lives in a
  # root-only file outside the store; see docs/beszel-synology.md.
  systemd.units."beszel-agent.service".text = ''
    [Unit]
    Description=Beszel agent
    After=network-online.target
    Wants=network-online.target
    RequiresMountsFor=/volume1

    [Service]
    ExecStart=${pkgs.beszel}/bin/beszel-agent
    EnvironmentFile=/volume1/@appdata/nix-system/secrets/beszel-agent.env
    Environment=PATH=${pkgs.smartmontools}/bin:/usr/bin:/bin
    Environment="HUB_URL=http://[2600:2b00:9b16:6d01::228]:8091"
    Environment="KEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINIxBO27YxooTl6NWl1Jf8v/AAanacdGhJf9VF1t2yds"
    Environment=DATA_DIR=/volume1/docker/beszel-agent/data
    Environment=EXTRA_FILESYSTEMS=/volume1
    Environment=SYS_SENSORS=/volume1/docker/beszel-agent/sensors
    Environment=PRIMARY_SENSOR=k10temp
    Environment=SMART_DEVICES=/dev/sata1:sat,/dev/sata2:sat,/dev/sata3:sat,/dev/sata4:sat,/dev/sata5:sat,/dev/sata6:sat,/dev/sata7:sat,/dev/sata8:sat
    CapabilityBoundingSet=CAP_SYS_RAWIO CAP_SYS_ADMIN CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
    Restart=always
    RestartSec=10
  '';
}
