# The fleet's Nix binary cache: this NAS's store, served by its nix-daemon over
# ssh-ng. Hosts push every build here (modules/nixos/cache-push.nix) and
# substitute from it (modules/nixos/host-shared.nix), at home and away, over
# the tailnet:
#
#   ssh-ng://svc-nixcache@100.111.251.156  (host key pinned on the clients)
#
# svc-nixcache's keys are the clients' *host* keys, each forced to
# `nix-daemon --stdio`. It is in `administrators` only because DSM gives other
# accounts /sbin/nologin, and sshd runs even a forced command through the
# login shell; its password is random and never used. The daemon serves it as
# an untrusted user, so every pushed path must carry a signature from a key in
# nix.conf's trusted-public-keys (system.nix).
{pkgs, ...}: let
  forced = key: ''restrict,command="/nix/var/nix/profiles/default/bin/nix-daemon --stdio" ${key}'';
  gib = n: n * 1024 * 1024 * 1024;
in {
  users.users.svc-nixcache = {
    description = "Nix binary cache (ssh-ng)";
    extraGroups = ["administrators"];
    authorizedKeys = map forced [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINRtF1Gu1NN25zb3ZWL+D2XBn2i0FszefxLVMwhItgOb nutmeg"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKaiGtVceXg9xJh0+jIIhFKZtnlNdPaWCZqSp0KNsb6r tuckles"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEZW19gGFVWa3uCxOv4CHItnUuucmNQiExpgMAqTUSNO Techcyte-DGQJV434PF"
    ];
  };

  # Collect by free space, not age: volume1 has ~4 TB free, so the cache only
  # shrinks when it starts to matter. GC roots (profiles, generations) stay.
  systemd.units."nix-store-gc.service" = {
    wantedBy = [];
    text = ''
      [Unit]
      Description=Collect Nix store garbage when /volume1 runs low
      RequiresMountsFor=/nix/store

      [Service]
      Type=oneshot
      Environment=PATH=${pkgs.coreutils}/bin
      Environment=GC_PATH=/volume1
      Environment=MIN_FREE=${toString (gib 300)}
      Environment=MAX_FREE=${toString (gib 600)}
      Environment=NIX_STORE=/nix/var/nix/profiles/default/bin/nix-store
      ExecStart=${pkgs.bash}/bin/bash ${./store-gc.sh}
    '';
  };
  systemd.units."nix-store-gc.timer" = {
    wantedBy = ["timers.target"];
    text = ''
      [Unit]
      Description=Daily Nix store free-space check

      [Timer]
      OnCalendar=*-*-* 04:30
      Persistent=true
    '';
  };
}
