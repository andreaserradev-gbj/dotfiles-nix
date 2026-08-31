# Declarative disk layout for hplaptop (disko).
#
# Mirrors geekom's shape — 512M vfat ESP + root filling the rest, both mounted
# by label — with the root label `hplaptop` so a by-label mount can never
# bind the wrong disk if two hosts ever meet in one machine. ESP is `BOOT`,
# shared across hosts because there is only one ESP per disk.
#
# Plain ext4, NO LUKS — settled in the PRD's Fixed Frame. This is a laptop,
# but Elisa is non-technical and a passphrase prompt in front of every boot
# is a brick risk that encryption-at-rest does not justify here.
#
# The device path below is REAL, captured on the box at install time
# (2026-08-27) — see the by-id node further down. It is no longer a placeholder.
# bootstrap.sh still refuses to run against any device path containing
# "PLACEHOLDER", which is the guard a fresh fork of this file relies on: set the
# path back to a PLACEHOLDER string if you ever re-template this host.
{
  disko.devices.disk.main = {
    type = "disk";

    # Real by-id node, captured on the box at install time (2026-08-27).
    # Whole-disk node, never a -partN symlink. Do NOT substitute /dev/sda or
    # /dev/nvme0n1: kernel enumeration order is not stable across boots, and
    # disko's destroy mode acts on whatever it resolves to. The by-id form
    # keeps the target unambiguous.
    device = "/dev/disk/by-id/nvme-INTEL_SSDPEKKF256G7H_BTPY807200UQ256D";

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
              "hplaptop"
            ]; # ext4 label -> by-label mount; must match hardware-configuration.nix
          };
        };
      };
    };
  };
}
