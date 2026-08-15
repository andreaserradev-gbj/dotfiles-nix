# Hardware facts for the UTM aarch64 VM, captured by nixos-generate-config.
# The generated header ("Do not modify...") and `nixpkgs.hostPlatform =
# lib.mkDefault "aarch64-linux"` were stripped: the flake sets `system` for
# both hosts symmetrically and owns that decision — same reasoning as
# hosts/geekom/hardware-configuration.nix. fileSystems are hand-written to
# match hosts/vm/disk-config.nix's labels.
{
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "virtio_pci"
    "usbhid"
    "usb_storage"
    "sr_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
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
}
