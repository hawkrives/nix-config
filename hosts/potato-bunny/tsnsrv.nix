# tsnsrv: each service in tsnsrv.services gets a tailnet node of its own,
# https://<name>.vaquita-woodpecker.ts.net, proxying to its upstream. Same
# flags as the NixOS module on nutmeg and tuckles (modules from the tsnsrv
# flake), as plain systemd-219 units. tsnet is a userspace node, so this needs
# neither tailscaled nor port 443 on the host (DSM's nginx holds that).
#
# Ephemeral nodes: one that stops for long enough is removed from the tailnet,
# and comes back under the same name on its next start.
#
# The auth key is secrets/tsnsrv-authkey-potato-bunny.age, decrypted by
# activate: the "tsnsrv potato-bunny" OAuth client's secret, bare. A client
# mints keys carrying exactly its own tag set, so this one has only
# tag:tsnsrv-potato-bunny and nutmeg's has only tag:tsnsrv-nutmeg.
{
  config,
  lib,
  perSystem,
  ...
}: let
  inherit (lib) mkOption types;
  tsnsrv = perSystem.tsnsrv.default;
  stateRoot = "/volume2/@appdata/tsnsrv";
  authKey = config.age.secrets.tsnsrv-authkey.path;
in {
  options.tsnsrv.services = mkOption {
    default = {};
    description = "Tailnet names to publish, each proxying to `upstream`.";
    type = types.attrsOf (types.submodule {
      options.upstream = mkOption {
        type = types.str;
        example = "http://127.0.0.1:3010";
        description = "URL the node proxies to.";
      };
    });
  };

  config.age.secrets.tsnsrv-authkey.file = ../../secrets/tsnsrv-authkey-potato-bunny.age;

  config.systemd.units = lib.mapAttrs' (name: svc:
    lib.nameValuePair "nix-tsnsrv-${name}.service" {
      text = ''
        [Unit]
        Description=tsnsrv: ${name}.vaquita-woodpecker.ts.net -> ${svc.upstream}
        ConditionPathIsMountPoint=/volume2
        OnFailure=notify-failure@%n.service
        After=network-online.target
        Wants=network-online.target

        [Service]
        ExecStartPre=/bin/mkdir -p -m 0700 ${stateRoot}/${name}
        ExecStart=${tsnsrv}/bin/tsnsrv -stateDir=${stateRoot}/${name} -authkeyPath=${authKey} -name=${name} -ephemeral=true -funnel=false -plaintext=false -listenAddr=:443 -stripPrefix=true -tag=tag:tsnsrv-potato-bunny ${svc.upstream}
        Restart=on-failure
        RestartSec=10
      '';
    })
  config.tsnsrv.services;
}
