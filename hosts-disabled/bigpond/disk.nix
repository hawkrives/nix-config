# disko layout for bigpond (single internal NVMe on the T2 MacBook, UEFI/systemd-boot).
# Confirm the disk node at install time with `lsblk` (T2 internal SSD => /dev/nvme0n1).
{ ... }:
{
  disko.devices.disk.main = {
    device = "/dev/nvme0n1";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
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
            mountpoint = "/"; # /nix lives here — the whole SSD is the store + builder scratch
          };
        };
      };
    };
  };
}
