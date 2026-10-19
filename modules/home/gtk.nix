# The niri session's GTK-side theming: the Papirus icon theme (Mocha folder
# colors) and the wallpaper asset Noctalia displays. Gated on the same option
# as modules/nixos/desktop.nix AND on `session == "niri"` — hplaptop runs plain
# GNOME, and the VM's cage+foot kiosk must not pick it up. The GTK3 THEME died
# with the variant world: catppuccin-gtk was archived in 2024 because GTK
# theming has no stable API, and its failure mode was a buggy theme in a
# shrinking set of apps as they move to GTK4. Libadwaita surfaces were never
# reachable by it anyway (desktop.nix's `accent-color` is the lever there).
{
  lib,
  osConfig,
  pkgs,
  ...
}:

lib.mkIf (osConfig.local.desktop.enable && osConfig.local.desktop.session == "niri") {
  gtk = {
    enable = true;

    # The icon theme IS honoured by GTK4/libadwaita — it is the one theming
    # surface that crosses the GTK3/GTK4 boundary. The package bakes the Mocha
    # folder colors in at build time; the resulting directory is `Papirus-Dark`,
    # standard Papirus naming.
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.catppuccin-papirus-folders.override {
        flavor = "mocha";
        accent = "mauve";
      };
    };
  };

  # NOT setting `home.pointerCursor`: GNOME on Wayland resolves `cursor-theme`
  # by DIRECTORY name, while this package ships `catppuccin-mocha-mauve-cursors`
  # and its index.theme also lacks `Inherits=hicolor`, so undefined shapes fail
  # to resolve. Setting the Name= value instead renders a white square. Left
  # unset: the default Adwaita cursor is neutral against Mocha. Re-enable only
  # with a wrapper that fixes both, or if upstream packaging is fixed.
  # home.pointerCursor = { ... };

  # Through `xdg.dataFile` so the path in config/noctalia/config.toml's
  # `[wallpaper.default]` carries no nix store hash: a wallpaper package bump
  # would otherwise leave Noctalia pointing at a store path that no longer
  # exists.
  home.packages = [ pkgs.nixos-artwork.wallpapers.catppuccin-mocha ];

  xdg.dataFile."backgrounds/catppuccin-mocha.png".source =
    "${pkgs.nixos-artwork.wallpapers.catppuccin-mocha}/share/backgrounds/nixos/nixos-wallpaper-catppuccin-mocha.png";
}
