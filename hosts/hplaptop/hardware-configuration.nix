# Hardware facts for hplaptop — TEMPLATE, to be filled at install time.
#
# Captured on the box itself with:
#   nixos-generate-config --no-filesystems --dir /tmp/cfg
# then copy the `boot.initrd.availableKernelModules` list here. The
# placeholder list below is empty on purpose — do NOT ship a guess.
#
# `fileSystems` below is hand-written, NOT generated. disko is an install-time
# tool in this repo — bootstrap.sh runs it standalone against a fetched copy
# of disk-config.nix, and the flake never imports disko.nixosModules.disko —
# so nothing else tells this host how to mount its root.
#
# Labels must match hosts/hplaptop/disk-config.nix: root label `hplaptop`,
# ESP label `BOOT`.
{
  modulesPath,
  ...
}:

{
  # Sets hardware.enableRedistributableFirmware with mkDefault. Inert while
  # default.nix sets it outright; kept as the generator emitted it so firmware
  # stays on if that line ever goes away.
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Captured on the box at install time (2026-08-27) via
  # nixos-generate-config --no-filesystems --dir /tmp/cfg. rtsx_pci_sdmmc is
  # the SD card reader — present on this ProBook, harmless in the initrd.
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "sd_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Root label is per-host (hplaptop) so a by-label mount can never bind the
  # wrong disk if two hosts ever meet in one machine. ESP is BOOT — shared
  # label across hosts because there is only one ESP per disk.
  fileSystems."/" = {
    device = "/dev/disk/by-label/hplaptop";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ ];

  # No `nixpkgs.hostPlatform`: the flake sets `system` for all hosts
  # symmetrically and owns that decision. The generated file reintroduced it
  # and it was stripped, as the other hardware-configuration.nix files require.
}
