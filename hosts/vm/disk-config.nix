# Declarative disk layout for the UTM dev VM (disko).
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/vda"; # UTM virtio disk
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00"; # EFI System Partition
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "fmask=0077"
              "dmask=0077"
            ];
            extraArgs = [
              "-n"
              "BOOT"
            ]; # FAT label -> by-label mount
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            extraArgs = [
              "-L"
              "nixos"
            ]; # ext4 label -> by-label mount
          };
        };
      };
    };
  };
}
