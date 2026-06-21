# Exposes `synologyMount` as a module argument for building NFS automount
# fileSystems entries against the Synology NAS. Used by nutmeg and tuckles.
{ lib, ... }:
let
  synology = "192.168.1.194";
  nfsMount =
    sharePath:
    {
      readOnly ? false,
    }:
    {
      fsType = "nfs";
      device = sharePath;
      options = [
        "nfsvers=4.1"
        "noatime"
        "_netdev"
        "x-systemd.automount"
        "x-systemd.idle-timeout=5m"
        "x-systemd.device-timeout=15s"
        "x-systemd.mount-timeout=15s"
      ]
      ++ lib.lists.optionals readOnly [ "ro" ];
    };
  synologyMount = sharePath: options: nfsMount "${synology}:${sharePath}" options;
in
{
  _module.args.synologyMount = synologyMount;
}
