# Hardware facts for geekom, captured on the machine itself in Phase 7 with
#   nixos-generate-config --no-filesystems --dir /tmp/cfg
#
# `fileSystems` below is hand-written, NOT generated. disko is an install-time
# tool in this repo — bootstrap.sh runs it standalone against a fetched copy of
# disk-config.nix, and the flake never imports disko.nixosModules.disko — so
# nothing else tells this host how to mount its root.
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

  # Generated on the box, 2026-08-07. Two absences are the evidence this file is
  # real rather than copied: no `virtio_pci` (that one belongs to the VM), and
  # no `ahci` — lspci shows this board carries no SATA controller at all, so the
  # placeholder's guess was wrong and the generated list wins.
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usb_storage"
    "usbhid"
    "sd_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # Labels must match hosts/geekom/disk-config.nix.
  fileSystems."/" = {
    device = "/dev/disk/by-label/geekom";
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

  # No `nixpkgs.hostPlatform`: the flake sets `system` for both hosts
  # symmetrically and owns that decision. The generated file reintroduced it and
  # it was stripped again, as Phase 7 requires.
  #
  # Also dropped from the generated output:
  #   hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  # default.nix already sets that to true outright. One owner, not two.
}
