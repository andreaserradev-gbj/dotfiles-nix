# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  user,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;

  # Cap the boot menu at the 10 most recent generations. Without this it grows
  # unbounded; cleared generations also linger in /boot/loader/entries until a
  # `nixos-rebuild boot`/`switch` reconciles the loader entries.
  boot.loader.systemd-boot.configurationLimit = 10;

  # aarch64 UTM VM: do NOT write boot entries into firmware NVRAM
  boot.loader.efi.canTouchEfiVariables = false;

  # Size the pre-cage *text* console (bootloader/tty) only — cage ignores this
  # and always uses the mode the host advertises as preferred. That is set on the
  # UTM side via '-global virtio-gpu-pci.xres/yres' QEMU args (see README, UTM
  # setup); keep this matched to those. Do NOT try drm.edid_firmware here: a
  # forced EDID empties the virtio-gpu mode list and kills the display.
  boot.kernelParams = [ "video=Virtual-1:1680x1050" ];

  # Network identity
  networking.hostName = "nixos"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # Set your time zone (lifted into user.nix — the one file a forker edits).
  time.timeZone = user.timeZone;

  programs.zsh.enable = true;

  # Account informations
  users.users.${user.username} = {
    isNormalUser = true;
    description = user.fullName;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    initialPassword = "nixos"; # throwaway
    openssh.authorizedKeys.keys = [ user.sshKey ];
  };

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
  ];

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Local graphical console
  services.spice-vdagentd.enable = true;

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

  # Modern `nix` CLI + flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Set-once: pin state-format defaults to the install release. Never bump casually.
  system.stateVersion = "26.05"; # Did you read the comment?

}
