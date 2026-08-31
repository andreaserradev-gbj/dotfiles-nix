# HP laptop — host-specific configuration.
# Intel i5, vanilla GNOME, no dev tooling, no sshd. Shared settings live in
# modules/nixos/common.nix. Suspend masked pending verification — see the
# comment on the systemd.targets block below.
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

  # Network identity
  networking.hostName = "hplaptop";

  # Real UEFI hardware, so writing boot entries into firmware NVRAM is both
  # safe and wanted. The VM sets this false — it has no persistent NVRAM.
  boot.loader.efi.canTouchEfiVariables = true;

  # 20s rather than the 5s default. This box's boot menu is its only recovery
  # path (no sshd, no network rebuild path), and 5 seconds is not enough to
  # catch when walking up to a machine that is already POSTing. The VM keeps
  # the default: it is reachable over ssh and rebuildable from the Mac.
  boot.loader.timeout = 20;

  # consoleMode was tried ("2", then "1" live-tested in loader.conf) to fix
  # the tiny boot-menu text: this HP firmware ignores the GOP resize in both
  # modes, so the setting is inert here and was reverted. The menu is only
  # used for recovery — arrows + Enter work regardless of text size.

  # Redistributable firmware blobs — Wi-Fi and Bluetooth firmware for the
  # laptop's combo radio. Omitting this is the difference between a working
  # desktop and a black screen with no network.
  hardware.enableRedistributableFirmware = true;

  # Intel i5 microcode updates (NOT hardware.cpu.amd — this is an Intel box).
  hardware.cpu.intel.updateMicrocode = true;

  # Graphical target: GDM + vanilla GNOME, pipewire, Brave. Defined in
  # modules/nixos/desktop.nix, which every host imports but only desktop
  # hosts switch on. `variant = "vanilla"` skips PaperWM + Catppuccin
  # theming — Elisa gets plain GNOME.
  local.desktop.enable = true;
  local.desktop.variant = "vanilla";
  local.desktop.libreoffice.enable = true; # Elisa needs Word/Excel for HR work

  # No dev tooling, no sshd, no authorized_keys. `local.dev.enable` defaults
  # to false — set explicitly here so the intent is legible at the host, not
  # just inferable from the absence of a line. This is the whole point of
  # this host: a non-technical user's machine with no admin surface area.
  local.dev.enable = false;

  # No gaming, no docker. Explicit for the same reason as dev.enable above.
  local.gaming.enable = false;
  local.docker.enable = false;

  # This host's user gets bash, not zsh. `common.nix` sets `shell = pkgs.zsh`
  # as a bare assignment (priority 100); `lib.mkForce` (priority 50) is lower,
  # so it wins without an eval conflict. See the "Account informations" comment
  # in modules/nixos/common.nix.
  #
  # Interpolated from `user.username` rather than spelled out: a rename in
  # user.nix would otherwise leave this defining a PHANTOM user that has only
  # a `.shell`, which trips NixOS's isNormalUser/isSystemUser assertion with an
  # error naming neither user.nix nor this line.
  users.users.${user.username}.shell = lib.mkForce pkgs.bash;

  # Wi-Fi powersave on a laptop trades a little interactive latency for
  # battery life — the opposite tradeoff from the mains-powered geekom box.
  # `common.nix` sets this false as a bare assignment (priority 100); this
  # `mkForce` (priority 50) is lower, so it wins. See the wifi.powersave
  # comment in modules/nixos/common.nix.
  networking.networkmanager.wifi.powersave = lib.mkForce true;

  # ...and that override is the pattern for laptop-class tuning generally: it
  # belongs in THIS file, not behind a marker field in user.nix. `user.nix`
  # once carried a `laptop = true` marker gating power-profiles-daemon in
  # common.nix; both were deleted, because GNOME already enables that daemon
  # via mkDefault — the gate set a value that was never unset, and it put a
  # machine attribute in the file that describes a person. Lid behaviour and
  # battery thresholds, when they arrive, go here.

  # Firmware updates for the laptop — fwupd + the LVFS. geekom has this too;
  # the VM does not (it has no real firmware to update).
  services.fwupd.enable = true;

  # Suspend was MASKED by default until verified on-site. Verified clean
  # 2026-08-27 (Andrea on-site): `systemctl suspend` → wake via power button
  # → journal showed a clean suspend/resume cycle, desktop and network
  # recovered. The mask block was removed after that test. If resume ever
  # regresses after a firmware update, restore the block from git history
  # (see hosts/geekom/default.nix:56-81 for the full reasoning).
  # Note: the mask covered GDM's greeter too; unmasked, GDM's greeter has its
  # own 900s idle suspend timer — same mechanism that bricked the geekom box.
  # If the greeter suspend ever hangs the box, re-mask rather than debugging
  # dconf.

  # Set-once: pin state-format defaults to the install release. Never bump casually.
  system.stateVersion = "26.05";
}
