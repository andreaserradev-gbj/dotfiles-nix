# UTM aarch64 VM — host-specific configuration.
# Shared settings live in modules/nixos/common.nix.
{
  pkgs,
  # The nixos-unstable nixpkgs instance, bound only on this host (flake.nix
  # `hostArgs`). Consumed for one package: opencode, below.
  unstablePkgs,
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
  # UTM side via '-global virtio-gpu-pci.xres/yres' QEMU args (see
  # doc/install-vm.md, UTM setup); keep this matched to those. Do NOT try
  # drm.edid_firmware here: a forced EDID empties the virtio-gpu mode list
  # and kills the display.
  boot.kernelParams = [ "video=Virtual-1:1680x1050" ];

  # Local graphical console
  services.spice-vdagentd.enable = true;

  # Dev tooling — nix-ld, ollama, opencode, nodejs, uv, jq, sshd — is gated
  # behind `local.dev.enable` in modules/nixos/dev.nix. This host flips it on.
  local.dev.enable = true;

  # opencode from nixos-unstable, exactly as on geekom: opencode's releases
  # land on unstable only, so 26.05's 1.15.10 lags the 1.18.x this VM gets.
  # The VM has no GPU and no ollama model worth running, so opencode here is
  # almost always talking to a remote/local provider — which is where the
  # 1.16-1.18 agent fixes actually land. Same userland/low-blast-radius
  # argument as geekom (doc/workflow.md, "Need a newer version before the next
  # release?"); the binding exists on this host in flake.nix `unstableHosts`.
  local.dev.opencodePackage = unstablePkgs.opencode;

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
