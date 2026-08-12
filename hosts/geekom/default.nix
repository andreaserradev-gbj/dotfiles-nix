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

  # THIS BOX CANNOT SUSPEND, so nothing is allowed to try. The firmware advertises
  # S0 S4 S5 — no S3 — and /sys/power/mem_sleep offers only [s2idle]. Resume hangs
  # hard: the journal stops dead at "Performing sleep operation 'suspend'" with not
  # one line after it, the display gets no signal, the radio drops off the LAN, and
  # a 10-second power-button hold is the only way back. Observed twice, 2026-08-09
  # and 2026-08-10.
  #
  # Masked at the SYSTEM level on purpose. The obvious fix — GNOME Settings →
  # Power → Automatic Suspend — writes to the logged-in user's dconf, and GDM's
  # greeter runs as its own user (uid 60578) with its own dconf and its own 900s
  # idle timer. That is exactly how the machine was lost on 2026-08-10: nobody had
  # logged in, so the greeter suspended it 15 minutes after boot while the user
  # session toggle sat there looking correct. Masking the targets is the only form
  # that covers the greeter, every user session, AND the power menu entry.
  #
  # hibernate and hybrid-sleep are masked too and cost nothing: both need swap, and
  # this disk layout creates none.
  #
  # Do NOT "fix" this with mem_sleep_default=deep. `deep` is absent from
  # mem_sleep, so the kernel parameter is a silent no-op that reads as a solution.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # Graphical target: GDM + GNOME, pipewire, Brave, Bluetooth, ghostty.
  # Defined in modules/nixos/desktop.nix, which every host imports but only
  # this one switches on.
  local.desktop.enable = true;

  # Gaming: Steam + Vulkan (RADV for the Radeon 890M). Defined in
  # modules/nixos/gaming.nix, which every host imports but only this one
  # switches on.
  local.gaming.enable = true;

  # Docker: dockerd + compose, for development. Defined in
  # modules/nixos/docker.nix, which every host imports but only this one
  # switches on. It also puts this user in the `docker` group, which is
  # root-equivalent — the module says what that does and does not cost.
  local.docker.enable = true;

  # Set-once: pin state-format defaults to the install release. Never bump casually.
  system.stateVersion = "26.05";
}
