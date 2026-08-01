# Declarative disk layout for geekom (disko).
#
# Mirrors the VM's shape — 512M vfat ESP + root filling the rest, both mounted
# by label — with two deliberate differences: an NVMe by-id device path, and
# the root label `geekom` so a by-label mount can never bind the wrong disk if
# the two ever meet in one machine.
#
# Plain ext4, NO LUKS — settled in the PRD's Fixed Frame. This box sits on a
# desk rather than travelling, and encryption would put a passphrase prompt in
# front of every otherwise-unattended boot.
{
  disko.devices.disk.main = {
    type = "disk";

    # PLACEHOLDER — replace in Phase 7 with the real path read off the box:
    #   ls -l /dev/disk/by-id/ | grep nvme
    # Do NOT substitute /dev/nvme0n1. Kernel enumeration order is not stable
    # across boots, and disko's destroy mode acts on whatever it resolves to.
    device = "/dev/disk/by-id/nvme-PLACEHOLDER-REPLACE-IN-PHASE-7";

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
              "geekom"
            ]; # ext4 label -> by-label mount; must match hardware-configuration.nix
          };
        };
      };
    };
  };
}
