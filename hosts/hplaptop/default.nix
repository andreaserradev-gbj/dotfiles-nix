# HP laptop — host-specific configuration.
# Intel i5, vanilla GNOME, no dev tooling, no sshd. Shared settings live in
# modules/nixos/common.nix. Suspend masked pending verification — see the
# comment on the systemd.targets block below.
{
  pkgs,
  lib,
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

  # Elisa's shell is bash, not zsh. `common.nix` sets `shell = pkgs.zsh` as a
  # bare assignment (priority 1500); `lib.mkForce` (priority 50) overrides it
  # without an eval conflict. See the comment in common.nix:34.
  users.users.elisa.shell = lib.mkForce pkgs.bash;

  # Wi-Fi powersave on a laptop trades a little interactive latency for
  # battery life — the opposite tradeoff from the mains-powered geekom box.
  # `common.nix` sets this false as a bare assignment (priority 1500); this
  # `mkForce` (priority 50) overrides it. See common.nix:23-32.
  networking.networkmanager.wifi.powersave = lib.mkForce true;

  # Firmware updates for the laptop — fwupd + the LVFS. geekom has this too;
  # the VM does not (it has no real firmware to update).
  services.fwupd.enable = true;

  # Suspend is MASKED by default on this box. Resume behavior on this
  # hardware is UNVERIFIED — the geekom firmware advertised S0/S4/S5 and
  # resume hung hard anyway (see hosts/geekom/default.nix:56-81). The same
  # class of quirk can hit any machine. Remove this block ONLY after
  # `systemctl suspend` resumes cleanly on-site:
  #   systemctl suspend          # wait 10s, wake via power button/lid
  #   journalctl -k -b -1        # look for a clean suspend/resume cycle
  # Elisa is non-technical — a hard hang is a brick from her perspective;
  # suspend is a nice-to-have, not a requirement.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # Set-once: pin state-format defaults to the install release. Never bump casually.
  system.stateVersion = "26.05";
}
