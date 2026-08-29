# Exposes `synologyMount` as a module argument for building NFS automount
# fileSystems entries against the Synology NAS. Used by nutmeg and tuckles.
{
  config,
  lib,
  utils,
  ...
}:
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
        # NB: no x-systemd.device-timeout. It only applies to device-backed
        # mounts, so on an NFS device string systemd's fstab generator ignores
        # it and says so, once per mount per generator run — 391 lines of
        # "'192.168.1.194:/volume1/…' is not a device path, ignoring
        # x-systemd.device-timeout=" in a single boot. mount-timeout is the one
        # that actually bounds an attempt here.
        "x-systemd.mount-timeout=15s"
      ]
      ++ lib.lists.optionals readOnly [ "ro" ];
    };
  synologyMount = sharePath: options: nfsMount "${synology}:${sharePath}" options;

  # Every mount this module produced, found by the NAS address rather than by a
  # hand-kept list, so the drop-in below can't drift from the shares in use.
  synologyMounts = lib.filter (fs: fs.device != null && lib.hasPrefix "${synology}:" fs.device) (
    lib.attrValues config.fileSystems
  );
in
{
  _module.args.synologyMount = synologyMount;

  # Drop the start rate limit on these mounts. The stock five starts per ten
  # seconds is far too tight for an automount: a process that touches an
  # unreachable share retries at once, so a few seconds without the NAS spend
  # the whole budget. The .mount then sticks at start-limit-hit and the
  # .automount dies with mount-start-limit-hit, and neither recovers on its
  # own. Once anything mounts the share directly, the path is a mount point
  # with no automount behind it, and systemd refuses to start an automount
  # over a mount point — so every later activation fails remote-fs.target.
  # Without the limit a blip just retries; mount-timeout above still bounds
  # each attempt.
  systemd.units = lib.listToAttrs (
    map (
      fs:
      lib.nameValuePair "${utils.escapeSystemdPath fs.mountPoint}.mount" {
        overrideStrategy = "asDropin";
        text = ''
          [Unit]
          StartLimitIntervalSec=0
        '';
      }
    ) synologyMounts
  );
}
