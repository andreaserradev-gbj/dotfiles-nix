# PLACEHOLDER — this file was NOT produced by nixos-generate-config.
#
# It is hand-written so that `nixosConfigurations.geekom` evaluates before the
# hardware exists, which is the whole point of this phase: catch typos and
# undefined options with zero hardware. Phase 7 replaces this file WHOLESALE
# with real generated output from the actual machine.
{
  ...
}:

{
  # Sentinel. Makes it impossible for a stale placeholder to ship quietly —
  # every eval and every nixos-rebuild on geekom prints this until Phase 7
  # overwrites the file. It disappears when the file does; do not delete it on
  # its own.
  warnings = [
    "geekom/hardware-configuration.nix is a PLACEHOLDER — regenerate it with nixos-generate-config (Phase 7) before trusting any build."
  ];

  # Expected initrd set for this box: NVMe root, AHCI for the SATA bay, xHCI +
  # USB HID so a keyboard works at the boot console.
  #
  # Note what is ABSENT: virtio_pci. That module is the VM's, and its presence
  # here after Phase 7 would be positive evidence the file was copied rather
  # than generated.
  boot.initrd.availableKernelModules = [
    "nvme"
    "ahci"
    "sd_mod"
    "xhci_pci"
    "usbhid"
    "usb_storage"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
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

  # No `nixpkgs.hostPlatform` here on purpose: the flake sets `system` for
  # both hosts symmetrically and owns that decision. Strip it again if Phase
  # 7's generated file reintroduces it.
}
