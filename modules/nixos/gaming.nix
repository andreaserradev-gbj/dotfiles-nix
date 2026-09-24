# The gaming seam. Imported by EVERY host through commonModules, but wholly
# inert unless the host sets `local.gaming.enable`. The VM leaves it off: it
# runs a cage+foot kiosk on a software renderer and has no GPU to game on.
# `local.*` is this repo's own option namespace; nothing upstream owns it.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.gaming;
in
{
  options.local.gaming.enable = lib.mkEnableOption "the gaming stack (Steam, Vulkan)";

  config = lib.mkIf cfg.enable {
    # Steam is unfree and needs TWO entries in common.nix's allowUnfreePredicate:
    # `lib.getName` returns the pname, which is both `steam` and `steam-unwrapped`
    # — allowing one fails eval on the other, naming only that one.
    programs.steam.enable = true;

    # Vulkan userspace drivers (RADV for the Radeon 890M) via mesa; the kernel
    # side (amdgpu) comes from the geekom host.
    #
    # Redundant today — programs.steam sets both — but the need belongs to the
    # gaming stack: 32-bit userspace is for Steam's 32-bit games. Redundant, not
    # accidental.
    hardware.graphics.enable = true;
    hardware.graphics.enable32Bit = true;

    # FPS + GPU clock + utilisation, which is what separates a bandwidth limit
    # from a governor that never ramps (Steam's counter shows neither). Per game:
    # `mangohud %command%`. 64-bit only (32-bit needs pkgsi686Linux.mangohud).
    environment.systemPackages = [ pkgs.mangohud ];

    # Raises the CPU governor only while a game runs, so the box does not idle
    # pinned at `performance` at its GDM screen. Per game: `gamemoderun %command%`.
    programs.gamemode.enable = true;
  };
}
