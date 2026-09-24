# Catppuccin Mocha theming for GNOME: GTK3 apps, the icon theme, the wallpaper.
# Gated on the same option as modules/nixos/desktop.nix AND on
# `variant == "full"` — hplaptop is vanilla, and the VM's cage+foot kiosk must
# not pick it up. What it cannot reach is deliberate: libadwaita surfaces
# (modules/home/desktop.nix's `accent-color` is the honest lever there), GNOME
# Shell chrome (the `user-themes` extension over catppuccin-gtk's version-skewed
# shell CSS risks a broken-looking shell) and GDM (modules/nixos/desktop.nix).
# catppuccin-gtk was archived in 2024 because GTK theming has no stable API: the
# build stays, the failure mode is a buggy theme in specific apps, and it covers
# a shrinking set as apps move to GTK4.
{
  lib,
  osConfig,
  pkgs,
  ...
}:

lib.mkIf (osConfig.local.desktop.enable && osConfig.local.desktop.variant == "full") {
  gtk = {
    enable = true;

    # The override args are validated by an `lib.checkListOfEnum` in package.nix,
    # so a typo fails at eval time rather than producing a silently-wrong theme.
    # `theme.name` must match the directory the override produces:
    # `catppuccin-mocha-mauve-standard`, with no `+default` suffix.
    theme = {
      name = "catppuccin-mocha-mauve-standard";
      package = pkgs.catppuccin-gtk.override {
        variant = "mocha";
        accents = [ "mauve" ];
      };
    };

    # The icon theme IS honoured by GTK4/libadwaita, unlike `gtk-theme` — it is
    # the one theming surface that crosses the GTK3/GTK4 boundary. The package
    # bakes the Mocha folder colors in at build time; the resulting directory is
    # `Papirus-Dark`, standard Papirus naming.
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

  # Through `xdg.dataFile` so the dconf `picture-uri` in desktop.nix points at a
  # stable path with no nix store hash in it; `home.packages` also lists the
  # package so GNOME's Backgrounds panel offers `catppuccin-mocha`.
  home.packages = [ pkgs.nixos-artwork.wallpapers.catppuccin-mocha ];

  xdg.dataFile."backgrounds/catppuccin-mocha.png".source =
    "${pkgs.nixos-artwork.wallpapers.catppuccin-mocha}/share/backgrounds/nixos/nixos-wallpaper-catppuccin-mocha.png";
}
