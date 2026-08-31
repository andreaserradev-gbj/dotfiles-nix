# Catppuccin Mocha theming for the GNOME desktop. Gated on the SAME option as
# the NixOS half (modules/nixos/desktop.nix) so the VM kiosk — which runs a
# cage+foot stack and never starts GNOME — cannot pick this up. Additionally
# gated on `variant == "full"`: a `vanilla` host (hplaptop) gets plain GNOME
# with no Catppuccin theming. Default `"full"` keeps geekom themed. That
# default was originally chosen to hold geekom's drvPath still; hash stability
# is no longer a goal in itself (see home.nix for the invariant that replaced
# it), but the default stands on its own merit — it is what geekom wants.
#
# What this DOES theme:
#   - GTK3 apps          (catppuccin-gtk v1.0.3, archived but still in nixpkgs)
#   - the cursor         (catppuccin-cursors.mochaMauve — fully maintained)
#   - the wallpaper      (nixos-artwork.wallpapers.catppuccin-mocha, 4K)
#
# What this does NOT theme, on purpose:
#   - libadwaita surfaces (Settings, Files, Text Editor…). GNOME 42+ apps
#     hardcode their own stylesheet and refuse user CSS. The closest honest
#     lever is the native `accent-color` (set in desktop.nix's dconf block),
#     which recolors selection/focus/buttons inside every libadwaita app.
#   - the GNOME Shell chrome (top bar, menus, notifications). Theming it
#     needs the `user-themes` extension + catppuccin-gtk's stale `gnome-shell/`
#     CSS targeted at a 2024 Shell; on GNOME 50.4 that stylesheet is
#     version-skewed and can produce a broken-looking or fail-to-load shell.
#     Skipped for the same reason the upstream port was archived: no
#     confidence it won't break between GNOME releases.
#   - GDM, entirely — GTK, wallpaper, shell AND cursor. The greeter keeps its
#     stock Adwaita look; the cursor specifically is blocked by the same
#     upstream catppuccin-cursors packaging issue described at the bottom of
#     this file. The login screen is visible for ~2s per boot, and a failed
#     greeter means a black screen recovered via TTY, so the regret-risk of
#     styling it is not worth the payoff. See modules/nixos/desktop.nix, where
#     gdm lives, for the same decision stated from the NixOS side.
#
# The catppuccin-gtk port was archived by its maintainers in June 2024
# (issue #262) with the note that GTK theming has no stable API and each
# GNOME release can render a theme buggy for one set of users while fixing
# it for another. nixpkgs still ships v1.0.3 with forward-compat patches
# (python-3.14.patch at the time of writing); the build is stable, the
# failure mode is visual glitches in specific apps, not system breakage.
# Realistic horizon: the theme keeps building for years but applies to a
# shrinking set of apps as they migrate GTK3 → GTK4/libadwaita.
{
  lib,
  osConfig,
  pkgs,
  ...
}:

lib.mkIf (osConfig.local.desktop.enable && osConfig.local.desktop.variant == "full") {
  # The GTK theme package, overridden to Mocha + Mauve. The override args are
  # validated by an `lib.checkListOfEnum` in package.nix, so a typo here fails
  # at eval time rather than producing a silently-wrong theme. `accents`
  # takes a list because upstream's build.py accepts multiple; one is the
  # common case. The resulting theme directory name is
  # `catppuccin-mocha-mauve-standard` — no `+default` suffix, that's the
  # upstream install.py naming and nixpkgs' build.py invocation does not add
  # it. `gtk.theme.name` below must match this directory name exactly.
  gtk = {
    enable = true;

    theme = {
      name = "catppuccin-mocha-mauve-standard";
      package = pkgs.catppuccin-gtk.override {
        variant = "mocha";
        accents = [ "mauve" ];
      };
    };

    # Icon theme. Papirus-Dark recolored with Catppuccin Mocha Mauve folder
    # colors via catppuccin-papirus-folders. Unlike `gtk-theme` (which
    # libadwaita ignores), the icon theme IS honored by GTK4/libadwaita —
    # `GtkIconTheme` reads `org.gnome.desktop.interface icon-theme` in both
    # GTK3 and GTK4 — so this reaches Nautilus, Settings, Text Editor and
    # every other GNOME app that the GTK theme cannot touch. It is the one
    # theming surface that crosses the GTK3/4 boundary cleanly.
    #
    # catppuccin-papirus-folders is a build-time package: at nix-build it
    # copies the full Papirus icon theme, overlays Catppuccin folder SVGs,
    # runs the papirus-folders recoloring script with `-C cat-mocha-mauve`
    # to bake the folder colors in, and generates the icon cache. The
    # result is just static SVGs — no runtime scripts, no daemons, no
    # activation hooks. Icon themes don't depend on GNOME Shell version,
    # so there's no version-skew risk (unlike the cursor or shell themes).
    #
    # The `.override` args are validated by `lib.checkListOfEnum` in
    # package.nix, so a typo fails at eval time. The resulting theme
    # directory is `Papirus-Dark` (standard Papirus naming, unchanged by
    # the catppuccin overlay — the overlay only replaces folder SVGs).
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.catppuccin-papirus-folders.override {
        flavor = "mocha";
        accent = "mauve";
      };
    };
  };

  # NOT setting `home.pointerCursor` here. The catppuccin-cursors package
  # ships its theme directory as `catppuccin-mocha-mauve-cursors` (hyphenated),
  # but GNOME on Wayland resolves `cursor-theme` by DIRECTORY name, not by the
  # `Name=` field inside index.theme. Setting `cursor-theme = "Catppuccin Mocha
  # Mauve"` (the Name= value, with spaces) therefore finds no matching
  # directory and GNOME falls back to a white square. Setting it to
  # `catppuccin-mocha-mauve-cursors` would work, but the package's index.theme
  # also lacks `Inherits=hicolor`, so shapes the theme does not define would
  # still fail to resolve on Wayland. Both issues are fixable with a
  # `runCommand` wrapper that renames the directory and patches index.theme,
  # but the result is fragile against upstream changes and was visibly broken
  # on the first test. Rather than ship a cursor customization that needs
  # patching to work at all, it is left unset: GNOME uses its default Adwaita
  # cursor, which is neutral against Mocha and has no discovery issues.
  # Re-enable deliberately if the upstream packaging is fixed, or if a
  # wrapper that handles both the directory name and the Inherits line is
  # worth maintaining for the visual payoff of a matching cursor.
  # home.pointerCursor = { ... };

  # Wallpaper. The 4K Catppuccin Mocha PNG from nixos-artwork (also archived,
  # but a static PNG does not bit-rot). Shipped as a stable-path symlink via
  # `xdg.dataFile` so the dconf `picture-uri` in desktop.nix can point at
  # `${config.home.homeDirectory}/.local/share/backgrounds/catppuccin-mocha.png`
  # without baking a nix store hash into the URI.
  #
  # `home.packages` ALSO adds the wallpaper package so GNOME's Backgrounds
  # panel lists `catppuccin-mocha` as a selectable entry.
  home.packages = [ pkgs.nixos-artwork.wallpapers.catppuccin-mocha ];

  xdg.dataFile."backgrounds/catppuccin-mocha.png".source =
    "${pkgs.nixos-artwork.wallpapers.catppuccin-mocha}/share/backgrounds/nixos/nixos-wallpaper-catppuccin-mocha.png";
}
