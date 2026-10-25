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
  nix.package = lix;
  profileExtra = [pkgs.cacert];

  # /etc/nix is a bind mount of /volume1/nix/etc (set up by the boot task), so
  # this lands on the volume and survives DSM updates.
  #
  # Substituters: cache.nixos.org and nix-community only. The NAS can't reach
  # pantry: DSM's tailscale runs in userspace mode, so tailnet addresses are
  # unroutable from here. Closures built elsewhere arrive by `nix copy` from
  # nutmeg, signed with the fleet keys trusted below.
  environment.etc."nix/nix.conf".text = ''
    build-users-group = nixbld
    trusted-users = root hawken
    experimental-features = nix-command flakes
    sandbox = true
    max-jobs = auto
    substituters = https://cache.nixos.org https://nix-community.cachix.org
    trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs= nutmeg:6F0E+NkIvpTI0d4QSvrDb3+LYhrQwXkYjqgI9etpuEw= pantry:eH1y5GJInQcb8pW/gXQq5GiMiszHIjhqpeMgktIDOQA= potato-bunny:i8Ab1IPNDKp9EWfmFDZIvMm70c+D435UlIsVFhJO3ts= tuckles:QXDvYTGgHgAIo/EzWTn/UcTuKZEP1MqsQsX9/3apQsc=
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
