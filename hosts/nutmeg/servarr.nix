{...}: let
  nfsOptions = [
    "nfsvers=4.1"
    "noatime" # we do not care about tracking the access time
    "_netdev" # ensure it's treated as a network fs, rather than local
    "x-systemd.automount" # enable mounting on first access
    "x-systemd.idle-timeout=5m" # unmount after this long
    "x-systemd.device-timeout=15s" # wait for a device to show up before giving up
    "x-systemd.mount-timeout=15s" # grace period for the actual mount call
  ];
  readOnlyNfs = nfsOptions ++ ["ro"];
in {
  fileSystems."/srv/photos" = {
    fsType = "nfs";
    device = "192.168.1.194:/volume1/media-photos";
    options = readOnlyNfs;
  };
}
