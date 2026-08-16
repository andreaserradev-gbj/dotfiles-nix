# Home-Manager half of the desktop seam, gated on the SAME option as the
# NixOS half. `osConfig` is auto-injected because Home Manager runs as a NixOS
# module here, so this needs no extraSpecialArgs wiring in the flake.
#
# This ADDS ghostty. It does NOT replace foot. foot stays enabled on both
# hosts: it is the VM's login program (services.cage launches it directly) and
# geekom's fallback if a GPU-accelerated terminal ever misbehaves.
{
  lib,
  osConfig,
  config,
  ...
}:

lib.mkIf osConfig.local.desktop.enable {
  programs.ghostty = {
    enable = true;

    settings = {
      # Catppuccin Mocha ships built into ghostty, so unlike foot.nix this
      # needs no hand-transcribed palette — but the intent is identical: both
      # terminals must look the same as each other and as the Mac.
      theme = "Catppuccin Mocha";

      font-family = "JetBrainsMono Nerd Font";
      font-size = 14;

      # foot's `pad = "8x8"` spelled the way ghostty spells it.
      window-padding-x = 8;
      window-padding-y = 8;
    };
  };

  # PaperWM enable state. The extension PACKAGE is installed on the NixOS side
  # (modules/nixos/desktop.nix) because GNOME Shell loads extensions from a
  # system path Home Manager cannot reach. The ENABLE state, however, is
  # per-user dconf under org.gnome.shell, so it belongs HERE.
  #
  # `programs.dconf.enable` is already true on the NixOS side — the GNOME
  # module (services.desktopManager.gnome.enable → core-os-services) sets it,
  # and the HM dconf module's activation step needs it. No NixOS-side addition
  # was required for this.
  #
  # `enabled-extensions` is the list GNOME Shell consults at startup. Adding
  # the UUID here enables PaperWM declaratively on every login; the Extensions
  # app's toggle becomes a read-only view of this state. `disabled-extensions`
  # is set empty on purpose — see the note below.
  #
  # GNOME Shell's `enabled-extensions` / `disabled-extensions` /
  # `disable-user-extensions` keys are the three it consults, and they are a
  # union rather than a toggle: an extension listed in BOTH enabled and
  # disabled is ENABLED (enabled wins). The HM dconf module only writes the
  # keys named here and resets keys removed between generations, so leaving
  # `disabled-extensions` unset (rather than `[]`) lets GNOME Shell keep
  # whatever the user toggled off in the Extensions app, and those entries
  # would still win over anything added here only because enabled wins —
  # which is the wrong outcome. Setting it to `[]` makes this config the
  # single source of truth: nothing the user disables in the GUI survives a
  # rebuild. That is the intent here, because a rebuild that silently
  # re-enables something the user thought they had turned off is worse than
  # the GUI toggle being inert.
  #
  # The Catppuccin theming keys live HERE and not in gtk.nix because dconf is
  # per-user state and this is the file that already owns the user's dconf
  # for the GNOME desktop. gtk.nix owns the PACKAGES (GTK theme, cursor,
  # wallpaper); this block owns the GNOME SETTINGS that select them.
  dconf.settings = {
    "org/gnome/shell" = {
      enabled-extensions = [ "paperwm@paperwm.github.com" ];
      disabled-extensions = [ ];
    };

    # Prefer-dark. GNOME's own setting; covers every app that respects
    # `color-scheme` (libadwaita + most GTK4 apps). The Catppuccin GTK theme
    # is dark by construction so GTK3 apps are dark regardless, but this
    # makes the libadwaita apps that the GTK theme CAN'T reach at least use
    # their dark variant.
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";

      # Native accent color (GNOME 47+). There is no `mauve`; `purple` is the
      # closest to Catppuccin Mocha Mauve (#cba6f7) — more saturated than the
      # palette swatch but the same hue family. This recolors selection
      # highlights, focus rings, switches and buttons inside every libadwaita
      # app, which is the one surface the GTK theme cannot touch. It is the
      # honest bridge between "theme GTK3" and "leave libadwaita alone".
      accent-color = "purple";

      # Selects the GTK3 theme. The name is the directory name under
      # share/themes/, which catppuccin-gtk.override produces as
      # `catppuccin-mocha-mauve-standard` (no `+default` suffix — that's the
      # upstream install.py naming convention, not nixpkgs' build.py one).
      gtk-theme = "catppuccin-mocha-mauve-standard";

      # Selects the icon theme. Unlike `gtk-theme`, this IS honored by
      # GTK4/libadwaita — `GtkIconTheme` reads this key in both GTK3 and
      # GTK4 — so Nautilus, Settings, Text Editor and every other GNOME app
      # picks up Papirus-Dark with Catppuccin Mocha Mauve folder colors.
      # See modules/home/gtk.nix for how the package is built.
      icon-theme = "Papirus-Dark";
    };

    # Wallpaper. `picture-uri-dark` is what GNOME 42+ reads under
    # `prefer-dark`; `picture-uri` is the light-mode fallback and is set to
    # the same image so a future `color-scheme` flip does not drop to a
    # default wallpaper. The path is a stable symlink installed by
    # xdg.dataFile in gtk.nix — NOT a nix store path with a hash — so a
    # wallpaper package bump never leaves a stale URI here.
    #
    # `picture-uri` is a `file://` URL, so the absolute path is unavoidable
    # in the value. The username is taken from HM's evaluated
    # `config.home.homeDirectory` rather than hardcoded so this file stays
    # fork-friendly: the only username literal in the repo is user.nix.
    # `config.xdg.dataHome` would be the cleaner reference, but it resolves
    # to `$HOME/.local/share` which GNOME's background reader does NOT
    # expand — the URI must be a real absolute path, so homeDirectory +
    # the literal suffix it is.
    #
    # `picture-options = "zoom"` (per-display) is the safe default: the 4K
    # image scales down cleanly to any single display without distortion.
    # `"spanned"` would stretch one image across multiple monitors and
    # needs a wider source to avoid artifacts; not in scope for one host.
    "org/gnome/desktop/background" = {
      picture-uri = "file://${config.home.homeDirectory}/.local/share/backgrounds/catppuccin-mocha.png";
      picture-uri-dark = "file://${config.home.homeDirectory}/.local/share/backgrounds/catppuccin-mocha.png";
      picture-options = "zoom";
    };

    # Lock-screen wallpaper. GNOME 43+ reads `picture-uri` from the
    # `screensaver` schema SEPARATELY from the desktop background — a detail
    # easy to miss, leaving the lock screen on GNOME's default while the
    # desktop is Mocha. Mirroring the same URI here keeps them in sync; if
    # you ever want a different lock-screen image, this is the key to change.
    "org/gnome/desktop/screensaver" = {
      picture-uri = "file://${config.home.homeDirectory}/.local/share/backgrounds/catppuccin-mocha.png";
      picture-options = "zoom";
    };
  };
}
