# Beszel hub: the web UI plus the PocketBase database holding every agent's
# metric history. On the NAS rather than a host it monitors, so it keeps
# alerting when nutmeg is down.
#
# Agents dial in over WebSocket (modules/nixos/beszel-agent.nix) to this
# host's tailnet address; the NAS's own agent uses loopback.
#
#   https://beszel.vaquita-woodpecker.ts.net   (tsnsrv.nix)
#     -> [::1]:8091 beszel-hub, data in /volume2/@appdata/beszel-hub
#
# 8091 is beszel's 8090 + 1, kept from when the hub shared a host with
# scanservjs; HUB_URL in every agent names it.
{pkgs, ...}: let
  hub = "${pkgs.beszel}/bin/beszel-hub";
  data = "/volume2/@appdata/beszel-hub";
  # The hub keeps beszel_data/ under its working directory. Pre-start steps run
  # as root (PermissionsStartOnly), so they drop to the hub account here.
  asHub = pkgs.writeShellScript "as-beszel-hub" ''
    cd ${data}
    exec ${pkgs.util-linux}/bin/setpriv --reuid=svc-beszel --regid=users --init-groups -- ${hub} "$@"
  '';
in {
  users.users.svc-beszel.description = "Beszel hub";

  tsnsrv.services.beszel.upstream = "http://[::1]:8091";

  # data.db holds the metric history and the admin account (auxiliary.db is
  # only PocketBase's request log). id_ed25519 is the hub's private key: a
  # restored hub with a fresh keypair would break every agent's KEY.
  appdataBackup.jobs.beszel-hub = {
    sqlite = ["beszel_data/data.db"];
    files = ["beszel_data/id_ed25519"];
  };

  systemd.units."beszel-hub.service".text = ''
    [Unit]
    Description=Beszel hub
    ConditionPathIsMountPoint=/volume2
    OnFailure=notify-failure@%n.service
    After=network-online.target
    Wants=network-online.target

    [Service]
    User=svc-beszel
    PermissionsStartOnly=true
    ExecStartPre=${pkgs.coreutils}/bin/install -d -o svc-beszel -m 0750 ${data}
    # Owns everything in its data dir, as StateDirectory= would.
    ExecStartPre=${pkgs.coreutils}/bin/chown -R svc-beszel ${data}
    ExecStartPre=${asHub} migrate up
    ExecStartPre=${asHub} migrate history-sync
    ExecStart=/bin/sh -c "cd ${data} && exec ${hub} serve --http=[::]:8091"
    Restart=on-failure
    RestartSec=5
  '';
}
