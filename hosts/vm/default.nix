# UTM aarch64 VM — host-specific configuration.
# Shared settings live in modules/nixos/common.nix.
{
  pkgs,
  user,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan. This also pulls in
    # profiles/qemu-guest.nix, which is where the virtio guest bits come from.
    ./hardware-configuration.nix
  ];

  # Network identity
  networking.hostName = "nixos"; # Define your hostname.

  # aarch64 UTM VM: do NOT write boot entries into firmware NVRAM
  boot.loader.efi.canTouchEfiVariables = false;

  # Size the pre-cage *text* console (bootloader/tty) only — cage ignores this
  # and always uses the mode the host advertises as preferred. That is set on the
  # UTM side via '-global virtio-gpu-pci.xres/yres' QEMU args (see README, UTM
  # setup); keep this matched to those. Do NOT try drm.edid_firmware here: a
  # forced EDID empties the virtio-gpu mode list and kills the display.
  boot.kernelParams = [ "video=Virtual-1:1680x1050" ];

  # Local graphical console
  services.spice-vdagentd.enable = true;

  # Dev tooling — nix-ld, ollama, opencode, nodejs, uv, jq, sshd — is gated
  # behind `local.dev.enable` in modules/nixos/dev.nix. This host flips it on.
  local.dev.enable = true;

  # cage: single-app kiosk Wayland compositor. It IS the login — its systemd
  # unit (cage-tty1) conflicts with getty@tty1 and autologins via a PAM
  # null-password session, launching one full-screen foot. No display manager.
  services.cage = {
    enable = true;
    user = user.username;
    program = "${pkgs.foot}/bin/foot";
    # -s keeps VT-switching on, so Ctrl+Alt+F2 still reaches a bare tty — the
    # real fallback if the compositor ever misbehaves.
    extraArguments = [ "-s" ];
    environment = {
      # Pure-CPU rendering: no usable GPU here, so bypass GL/EGL entirely.
      # (WLR_RENDERER_ALLOW_SOFTWARE=1 is NOT enough — EGL can't init on this guest.)
      WLR_RENDERER = "pixman";
      # Fix the VM cursor rendering at the wrong position.
      WLR_NO_HARDWARE_CURSORS = "1";
    };
  };

  systemd.services."cage-tty1".serviceConfig.WorkingDirectory = user.homeDirectory;

  # Set-once: pin state-format defaults to the install release. Never bump casually.
  system.stateVersion = "26.05"; # Did you read the comment?
}
