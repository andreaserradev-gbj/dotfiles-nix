# HP laptop — host-specific configuration.
# Intel i5, vanilla GNOME, no dev tooling, no sshd. Shared settings live in
# modules/nixos/common.nix.
{
  pkgs,
  lib,
  user,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "hplaptop";

  # NVRAM writes are safe and wanted on real UEFI hardware; the VM sets this false.
  boot.loader.efi.canTouchEfiVariables = true;

  # 20s rather than the 5s default: this boot menu is the only recovery path (no
  # sshd, no network rebuild path), and 5s is too short to catch on a cold walk-up.
  boot.loader.timeout = 20;

  # No `boot.loader.consoleMode`: "2" and "1" were both tried on this firmware
  # (live-tested in loader.conf) and it ignores the GOP resize either way.

  # Wi-Fi and Bluetooth firmware for the laptop's combo radio; without it: black
  # screen, no network.
  hardware.enableRedistributableFirmware = true;

  # Intel box — the AMD counterpart would do nothing here.
  hardware.cpu.intel.updateMicrocode = true;

  # GDM + vanilla GNOME (modules/nixos/desktop.nix, imported everywhere, enabled
  # on the desktop hosts). `variant = "vanilla"` skips PaperWM and Catppuccin.
  local.desktop.enable = true;
  local.desktop.variant = "vanilla";
  local.desktop.libreoffice.enable = true; # Elisa needs Word/Excel for HR work

  # No dev tooling, no sshd, no authorized_keys. `local.dev.enable` defaults to
  # false; set explicitly so the intent is legible at the host. This absence is
  # the point of the machine: a non-technical user's host with no admin surface.
  local.dev.enable = false;

  # No gaming, no docker either — explicit for the same reason.
  local.gaming.enable = false;
  local.docker.enable = false;

  # This host's user gets bash, not zsh: `common.nix` sets `shell = pkgs.zsh` as
  # a bare assignment (priority 100), and `lib.mkForce` (priority 50) is lower, so
  # it wins without an eval conflict. Interpolated from `user.username` rather than
  # spelled out — a literal would define a PHANTOM user with only a `.shell`,
  # tripping NixOS's isNormalUser assertion with an error naming neither file.
  users.users.${user.username}.shell = lib.mkForce pkgs.bash;

  # A laptop trades a little interactive latency for battery life — the opposite
  # of the mains-powered geekom box. Same priority trick as the shell above; the
  # reasoning for the default lives in modules/nixos/common.nix. Laptop-class
  # tuning generally belongs in THIS file, never behind a machine marker in
  # user.nix — lid behaviour and battery thresholds go here too.
  networking.networkmanager.wifi.powersave = lib.mkForce true;

  # Firmware updates through the LVFS; the VM has no real firmware to update.
  services.fwupd.enable = true;

  # Suspend works here and stays UNMASKED (verified on-site 2026-08-27 —
  # doc/bare-metal-hplaptop.md). If resume regresses after a firmware update,
  # restore the systemd.targets mask from git history rather than debugging dconf
  # (the full reasoning is in hosts/geekom/default.nix).

  # Set once at install; never bump (doc/workflow.md).
  system.stateVersion = "26.05";
}
