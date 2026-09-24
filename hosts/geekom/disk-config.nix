# Declarative disk layout for geekom (disko): 512M vfat ESP + root filling the
# rest, both mounted by label. Plain ext4, NO LUKS (PRD Fixed Frame) — this box
# sits on a desk rather than travelling, and encryption would put a passphrase
# prompt in front of every otherwise-unattended boot. Root label `geekom`, so a
# by-label mount can never bind the wrong disk.
{
  disko.devices.disk.main = {
    type = "disk";

    # Whole-disk by-id node, never a -partN symlink and never /dev/nvme0n1:
    # kernel enumeration order is not stable across boots, and disko's destroy
    # mode acts on whatever it resolves to. udev publishes three aliases for this
    # one disk — the `_1` form is namespace 1, not a second drive.
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
            ];
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
