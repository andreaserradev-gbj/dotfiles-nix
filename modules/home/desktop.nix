# Home-Manager half of the desktop seam, gated on the SAME option as the NixOS
# half; `osConfig` is auto-injected, so no flake wiring is needed.
#
# This ADDS ghostty and does NOT replace foot, which stays the VM's login program
# (services.cage launches it directly) and geekom's fallback terminal. ghostty is
# gated on `desktop.enable` ALONE (a vanilla host still wants a terminal); the
# dconf block below is gated on `variant == "full"` as well.
{
  lib,
  osConfig,
  config,
  user,
  ...
}:

lib.mkIf osConfig.local.desktop.enable {
  programs.ghostty = {
    enable = true;

    settings = {
      # Built into ghostty, unlike foot.nix's hand-transcribed palette; both
      # terminals must look the same as each other and as the Mac.
      theme = "Catppuccin Mocha";

      font-family = "JetBrainsMono Nerd Font";
      font-size = 14;

      # foot's `pad = "8x8"`, spelled the way ghostty spells it.
      window-padding-x = 8;
      window-padding-y = 8;

      # No decorations at all: no GTK headerbar, no borders. PaperWM already marks
      # the focused window, and `window-width` below is exact ONLY with
      # decorations off — ghostty's docs: on GTK the calculated grid size does not
      # account for them, so the cell-to-pixel mapping drifts by the headerbar
      # height. `gtk-titlebar` is not set (dead config when decoration is `none`)
      # and `auto` is deliberately skipped: on GNOME it resolves to client-side
      # decorations, i.e. the headerbar being removed.
      window-decoration = "none";

      # Grid cells, and BOTH keys are required — ghostty ignores the pair if only
      # one is set.
      #
      # Why they matter: when a window maps, PaperWM adopts its current frame
      # width for the column (tiling.js `tiledWidth ?? frame.width`) and never
      # re-pins it, so the terminal opens tiled at this width and Super+R keeps
      # cycling. A PaperWM winprop with `preferredWidth` was rejected: it
      # re-applies on every relayout, so any window opening would snap the
      # terminal back and undo the user's Super+R choice. window-height only
      # satisfies the both-keys rule — PaperWM forces full workarea height.
      #
      # 210 cells ≈ the golden-ratio `cycle-width-steps` step of geekom's 4K panel
      # minus PaperWM margins (0.61804 × (3840 − 2×16 − 16) ≈ 2354 px) at
      # ~11.2 px/cell for this font at size 14. If ghostty honored GNOME's
      # `text-scaling-factor`, ~168 would be right instead — decided by eye after
      # a rebuild; revisit this value first if the opened width misses a step.
      window-width = 210;
      window-height = 40;
    };
  };

  # Per-user GNOME state, in three chunks merged by mkMerge: shared, dock, and
  # `variant == "full"`.
  #
  # mkMerge, not a second `dconf.settings` definition: the module system does not
  # deep-merge two separately-defined attrsets from the same module.
  #
  # `programs.dconf.enable` is already true on the NixOS side (the GNOME module
  # sets it), and the extension PACKAGE is installed there too, because GNOME
  # Shell loads extensions from a system path Home Manager cannot reach. The
  # ENABLE state is per-user dconf, so it belongs here — as do the Catppuccin
  # SETTINGS; gtk.nix owns the packages they select.
  dconf.settings = lib.mkMerge [
    # Gated on the field being PRESENT (not defaulted to "us"): a host without
    # `keyboardLayout` keeps its dconf byte-identical, since writing an explicit
    # input source that matches the platform default would still take ownership of
    # a key GNOME manages. `user` is threaded via extraSpecialArgs.
    (lib.mkIf (user ? keyboardLayout) {
      "org/gnome/desktop/input-sources" = {
        sources = [
          (lib.hm.gvariant.mkTuple [
            "xkb"
            user.keyboardLayout
          ])
        ];
      };
    })
    # Launch keys: Super+Return → ghostty, Super+b → Brave, through the
    # media-keys schema like anything the "Custom Shortcuts" GUI writes. Gated on
    # `desktop.enable` only — both variants want them, and both have ghostty and
    # Brave in their profiles. Commands are bare binary names resolved through
    # PATH, so a package bump cannot strand the binding.
    #
    # Neither combo collides with a GNOME default (its terminal shortcut is
    # Ctrl+Alt+T), but `<Super>Return` DOES collide with PaperWM's `new-window`
    # default — trimmed in the full-variant chunk below, otherwise Shell
    # grab-order gives PaperWM the combo and this binding never fires on geekom.
    {
      "org/gnome/settings-daemon/plugins/media-keys" = {
        custom-keybindings = [
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
          "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
        ];
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
        name = "Terminal";
        command = "ghostty";
        binding = "<Super>Return";
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1" = {
        name = "Browser";
        command = "brave";
        binding = "<Super>b";
      };
    }
    # Dash to Dock, on BOTH variants — the package is ungated on the NixOS side.
    # Its `enabled-extensions` list merges by concatenation with the full-variant
    # chunk below, so geekom gets both extensions and hplaptop just the dock.
    #
    # `disabled-extensions = []` is deliberate: the three Shell keys are a union
    # (an extension in BOTH lists is ENABLED), and the HM dconf module only writes
    # keys named here. Leaving it unset would let a GUI toggle-off survive a
    # rebuild and win here only by accident of that union; `[]` makes this config
    # the single source of truth. A rebuild that silently re-enables something the
    # user turned off is worse than the GUI toggle being inert.
    {
      "org/gnome/shell" = {
        enabled-extensions = [ "dash-to-dock@micxgx.gmail.com" ];
        disabled-extensions = [ ];
      };

      # Hidden by default, revealed only on bottom-edge pressure: no reserved
      # band, so PaperWM's tiling area is untouched. Icon size picked live.
      "org/gnome/shell/extensions/dash-to-dock" = {
        autohide = true;
        dock-fixed = false;
        intellihide = false;
        require-pressure-to-show = false;
        dock-position = "BOTTOM";
        extend-height = false;
        dash-max-icon-size = 64;
        show-trash = false;
      };
    }
    (lib.mkIf (osConfig.local.desktop.variant == "full") {
      "org/gnome/shell" = {
        enabled-extensions = [ "paperwm@paperwm.github.com" ];
      };

      # PaperWM's `new-window` default includes '<Super>Return', which collides
      # with the terminal binding above: PaperWM grabs conflicting combos on
      # enable (overrideConflicts) and Shell grabs beat gsd media-keys, so
      # Super+Return would duplicate the focused window instead of launching
      # ghostty. Trimmed to just '<Super>n'; vanilla hosts never see this key.
      "org/gnome/shell/extensions/paperwm/keybindings" = {
        new-window = [ "<Super>n" ];
      };

      "org/gnome/desktop/interface" = {
        # Covers every app that respects `color-scheme` (libadwaita + most GTK4).
        color-scheme = "prefer-dark";

        # Native accent color (GNOME 47+). There is no `mauve`; `purple` is the
        # closest to Catppuccin Mocha Mauve (#cba6f7) — more saturated than the
        # palette swatch, same hue family. This is the honest bridge between
        # "theme GTK3" and "leave libadwaita alone": it recolors selection, focus
        # rings, switches and buttons in apps the GTK theme cannot touch.
        accent-color = "purple";

        # Fonts only; the XWayland root window stays at the native 3840×2160, so
        # games keep seeing the real panel. `scaling-factor` was rejected for the
        # same job because it rescales the whole output, and fractional scaling
        # inflates XWayland's root window to 7680×4320 (ceil to 2×) — games then
        # render four times the pixels.
        text-scaling-factor = 1.25;

        # Pinned to 1:1 (100%) for that same reason: GNOME's per-display default
        # picks 125% on a 4K panel at first login, which is exactly the fractional
        # case above. Integer 1 keeps the output native and XWayland honest.
        scaling-factor = lib.gvariant.mkUint32 1;

        # Selects the GTK3 theme directory produced by gtk.nix's override.
        gtk-theme = "catppuccin-mocha-mauve-standard";

        # Selects the icon theme; unlike `gtk-theme` this IS honored by
        # GTK4/libadwaita (`GtkIconTheme` reads it in both). The package is in
        # gtk.nix.
        icon-theme = "Papirus-Dark";
      };

      # `picture-uri-dark` is what GNOME 42+ reads under `prefer-dark`;
      # `picture-uri` is the light-mode fallback, set to the same image so a
      # `color-scheme` flip does not drop to GNOME's default. The path is the
      # stable symlink installed by xdg.dataFile in gtk.nix, not a store hash, so
      # a wallpaper package bump never leaves a stale URI behind.
      #
      # `picture-uri` is a `file://` URL, so an absolute path is unavoidable
      # there, and `config.xdg.dataHome` does not help: it resolves to
      # `$HOME/.local/share`, which GNOME's background reader does not expand.
      # Taking the username from HM's evaluated `homeDirectory` keeps the only
      # username literal in the repo in user.nix. `zoom` scales the 4K image down
      # cleanly to any single display; `spanned` would stretch it and needs a
      # wider source.
      "org/gnome/desktop/background" = {
        picture-uri = "file://${config.home.homeDirectory}/.local/share/backgrounds/catppuccin-mocha.png";
        picture-uri-dark = "file://${config.home.homeDirectory}/.local/share/backgrounds/catppuccin-mocha.png";
        picture-options = "zoom";
      };

      # GNOME 43+ reads the lock screen's wallpaper from the `screensaver` schema
      # SEPARATELY — easy to miss, leaving the lock screen on GNOME's default
      # while the desktop is Mocha.
      "org/gnome/desktop/screensaver" = {
        picture-uri = "file://${config.home.homeDirectory}/.local/share/backgrounds/catppuccin-mocha.png";
        picture-options = "zoom";
      };
    })
  ];
}
