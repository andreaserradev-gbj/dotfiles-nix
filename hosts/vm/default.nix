# UTM aarch64 VM — host-specific config; shared settings in modules/nixos/common.nix.
{
  pkgs,
  user,
  ...
}:

{
  imports = [
    # Hardware scan results; also pulls in profiles/qemu-guest.nix.
    ./hardware-configuration.nix
  ];

  networking.hostName = "nixos";

  # aarch64 UTM VM: do NOT write boot entries into firmware NVRAM
  boot.loader.efi.canTouchEfiVariables = false;

  # Sizes the pre-cage *text* console only — cage uses the host's advertised mode.
  # Do NOT add drm.edid_firmware: a forced EDID empties the virtio-gpu mode list
  # and kills the display (doc/vm-console.md).
  boot.kernelParams = [ "video=Virtual-1:1680x1050" ];

  # Local graphical console
  services.spice-vdagentd.enable = true;

  # Turns on the dev tooling that modules/nixos/dev.nix gates.
  local.dev.enable = true;

  # cage kiosk: the compositor IS the login, launching one full-screen foot
  # (doc/vm-console.md).
  services.cage = {
    enable = true;
    user = user.username;
    program = "${pkgs.foot}/bin/foot";
    # -s keeps VT-switching on, so Ctrl+Alt+F2 still reaches a bare tty.
    extraArguments = [ "-s" ];
    environment = {
      # Pure-CPU rendering, mandatory on this GPU-less guest (doc/vm-console.md).
      WLR_RENDERER = "pixman";
      # Fixes the cursor rendering at the wrong position.
      WLR_NO_HARDWARE_CURSORS = "1";
    };
  };

  systemd.services."cage-tty1".serviceConfig.WorkingDirectory = user.homeDirectory;

  # Set once at install; never bump (doc/workflow.md).
  system.stateVersion = "26.05";
}
