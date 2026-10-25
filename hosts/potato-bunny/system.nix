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
}
