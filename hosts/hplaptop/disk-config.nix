# Declarative disk layout for hplaptop (disko): 512M vfat ESP + root filling the
# rest, both mounted by label. Plain ext4, NO LUKS (PRD Fixed Frame) — Elisa is
# non-technical and a passphrase prompt in front of every boot is a brick risk
# that encryption-at-rest does not justify here. Root label `hplaptop`, so a
# by-label mount can never bind the wrong disk.
{
  disko.devices.disk.main = {
    type = "disk";

    # Real by-id whole-disk node. Never a -partN symlink, and never /dev/sda or
    # /dev/nvme0n1 — kernel enumeration order is not stable across boots and
    # disko's destroy mode acts on whatever it resolves to. bootstrap.sh refuses
    # any device path containing "PLACEHOLDER", so re-templating this host means
    # putting a placeholder string back here.
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
              "hplaptop"
            ]; # ext4 label -> by-label mount; must match hardware-configuration.nix
          };
        };
      };
    };
  };
}
