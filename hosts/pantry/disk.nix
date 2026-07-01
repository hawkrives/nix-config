# disko layout for the pantry cache VM (single 4 TB virtual disk, UEFI/systemd-boot).
# Confirm the disk node at install time with `lsblk` (virtio => /dev/vda).
{ ... }:
{
  disko.devices.disk.main = {
    device = "/dev/vda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00"; # EFI System Partition
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/"; # /nix lives here — the whole 4 TB is the store
          };
        };
      };
    };
  };
}
