# GEEKOM A9 Max — host-specific configuration.
# Ryzen AI 9 HX 370 (Zen 5), Radeon 890M (RDNA 3.5), 32GB DDR5, 2TB NVMe,
# MediaTek MT7925 Wi-Fi 7 + Bluetooth combo radio.
# Shared settings live in modules/nixos/common.nix.
{
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Network identity
  networking.hostName = "geekom";

  # Real UEFI hardware, so writing boot entries into firmware NVRAM is both
  # safe and wanted. The VM sets this false — it has no persistent NVRAM.
  boot.loader.efi.canTouchEfiVariables = true;

  # 20s rather than the 5s default. This box's boot menu is its only recovery
  # path, and 5 seconds is not enough to catch when walking up to a machine that
  # is already POSTing. The VM keeps the default: it is reachable over ssh and
  # rebuildable from the Mac, so a missed menu costs nothing there.
  boot.loader.timeout = 20;

  # Redistributable firmware blobs. Load-bearing THREE separate times here:
  #   1. amdgpu       — the Radeon 890M will not initialise without RDNA 3.5
  #                     microcode; the console falls back to simpledrm at best
  #   2. MT7925 Wi-Fi — MediaTek Wi-Fi 7
  #   3. MT7925 Bluetooth — the SAME combo radio, but its BT side is a separate
  #                     USB-attached device driven by btusb, needing its own
  #                     blob (BT_RAM_CODE_MT7925_1_1_hdr.bin)
  # Omitting this is the difference between a working desktop and a black
  # screen with no network and no keyboard-adjacent way to fix it.
  hardware.enableRedistributableFirmware = true;

  # Zen 5 microcode updates.
  hardware.cpu.amd.updateMicrocode = true;

  # Load amdgpu from the initrd so the console comes up on the real driver
  # rather than handing over from simpledrm partway through boot.
  #
  # Deliberately NOT set: `services.xserver.videoDrivers` (that is the X11
  # driver path — amdgpu is a kernel driver and KMS is automatic; naming it
  # there is a common copy-paste that does nothing useful), and
  # `hardware.amdgpu.opencl.enable` (ROCm). This box runs ollama as a CLOUD
  # client — see the note in modules/nixos/common.nix — so there is no local
  # inference to accelerate and no reason to pull in the ROCm closure.
  #
  # Also deliberately NOT set: `boot.kernelPackages`. The 26.05 default kernel
  # is new enough for both Strix Point and MT7925; pinning latest here would
  # trade a working default for a moving target.
  hardware.amdgpu.initrd.enable = true;

  # Graphical target: GDM + GNOME, pipewire, Brave, Bluetooth, ghostty.
  # Defined in modules/nixos/desktop.nix, which every host imports but only
  # this one switches on.
  local.desktop.enable = true;

  # Gaming: Steam + Vulkan (RADV for the Radeon 890M). Defined in
  # modules/nixos/gaming.nix, which every host imports but only this one
  # switches on.
  local.gaming.enable = true;

  # Set-once: pin state-format defaults to the install release. Never bump casually.
  system.stateVersion = "26.05";
}
