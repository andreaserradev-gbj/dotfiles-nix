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

    # Read off the box in Phase 7 (2026-08-07). WHOLE-DISK node, never a -partN
    # symlink. Do NOT substitute /dev/nvme0n1: kernel enumeration order is not
    # stable across boots, and disko's destroy mode acts on whatever it
    # resolves to.
    #
    # udev publishes three aliases for this single disk. The namespace-
    # qualified `nvme-WPBSN4M8-2TGP_LPH225091113977_1` and the opaque
    # `nvme-eui.00000000000000000c82d55091113977` both land on the same device.
    # The `_1` is namespace 1, NOT a second drive — only one NVMe is fitted and
    # the M.2 2230 slot is empty. The model/serial form is used here because it
    # is the one a reviewer can recognise in a diff.
    device = "/dev/disk/by-id/nvme-WPBSN4M8-2TGP_LPH225091113977";

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
