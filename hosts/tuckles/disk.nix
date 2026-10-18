# disko layout for the tuckles VM (single virtual disk, legacy BIOS/GRUB).
# Confirm the disk node at install time with `lsblk` (virtio => /dev/vda).
{...}: {
  disko.devices.disk.main = {
    device = "/dev/vda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02"; # BIOS boot partition for GRUB on GPT
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  # Root is the last partition on /dev/vda, so a bigger virtual disk from Synology
  # VMM grows into it: growPartition (configuration.nix) extends the partition at
  # boot and autoResize runs resize2fs before mounting.
  fileSystems."/".autoResize = true;
}
