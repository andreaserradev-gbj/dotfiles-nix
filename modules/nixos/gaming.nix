# The gaming seam. Imported by EVERY host through commonModules, but wholly
# inert unless the host sets `local.gaming.enable`. The VM leaves it off: it
# runs a cage+foot kiosk on a software renderer and has no GPU to game on.
#
# `local.*` is this repo's own option namespace — nothing upstream owns it, so
# there is no collision risk as more seams (hyprland, …) get added.
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
    # Steam. Unfree, so it needs entries in the allowUnfreePredicate list in
    # common.nix — see the note there about named predicates.
    #
    # It needs TWO of them. The predicate tests `lib.getName`, which returns the
    # pname, and Steam trips the unfree check twice under different pnames:
    # `steam` (the package under pkgs/by-name/st/steam-unwrapped/, whose pname
    # is NOT its directory name) and `steam-unwrapped`. Allowing only one fails
    # evaluation on the other, and the error names only the one it hit — so it
    # looks like the fix did not work rather than like a second entry is needed.
    programs.steam.enable = true;

    # Vulkan userspace drivers (RADV for the Radeon 890M) via mesa. The kernel
    # side (amdgpu) is already loaded by hardware.amdgpu.initrd in the geekom
    # host; this is the userspace half that makes Vulkan actually work.
    #
    # BOTH LINES ARE REDUNDANT TODAY: nixpkgs' programs.steam module sets
    # hardware.graphics.enable and enable32Bit itself (and steam-hardware, for
    # controller udev rules). They are stated anyway because the requirement
    # belongs to the gaming stack rather than to Steam specifically — 32-bit
    # userspace is needed because Steam ships 32-bit games, and it must not
    # leave silently if the launcher is ever swapped or upstream stops setting
    # it. Redundant, not accidental.
    hardware.graphics.enable = true;
    hardware.graphics.enable32Bit = true;

    # MangoHud shows FPS together with GPU clock and utilisation, which is what
    # separates a memory-bandwidth limit from a governor that never ramps.
    # Steam's own counter shows neither, and its overlay is unreliable under
    # Proton. Per-game Steam launch option: `mangohud %command%`.
    #
    # 64-bit only. A 32-bit title needs pkgsi686Linux.mangohud added as well.
    environment.systemPackages = [ pkgs.mangohud ];

    # gamemode raises the CPU governor for the lifetime of a game and drops it
    # afterwards, so the box does not sit pinned at `performance` while idle —
    # which matters here because this hardware idles at a GDM login screen.
    # Games opt in per title: `gamemoderun %command%`.
    programs.gamemode.enable = true;
  };
}
