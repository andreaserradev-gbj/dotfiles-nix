# Home-Manager half of the desktop seam, gated on the SAME option as the NixOS
# half; `osConfig` is auto-injected, so no flake wiring is needed.
#
# This ADDS ghostty and does NOT replace foot, which stays the VM's login program
# (services.cage launches it directly) and geekom's fallback terminal. ghostty is
# gated on `desktop.enable` ALONE (a desktop without a terminal is no desktop);
# the dconf block below is split by `session` — the GNOME session's keys
# (hplaptop) and the niri session's look keys (geekom).
{
  lib,
  osConfig,
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

      # No decorations at all: no GTK headerbar, no borders. The compositor
      # marks the focused window, and `window-width` below is exact ONLY with
      # decorations off — ghostty's docs: on GTK the calculated grid size does not
      # account for them, so the cell-to-pixel mapping drifts by the headerbar
      # height. `gtk-titlebar` is not set (dead config when decoration is `none`)
      # and `auto` is deliberately skipped: on GNOME it resolves to client-side
      # decorations, i.e. the headerbar being removed.
      window-decoration = "none";

      # Grid cells, and BOTH keys are required — ghostty ignores the pair if only
      # one is set. niri tiles new windows at its own default column width and
      # ignores the client's size request there, so this pair governs the
      # floating case (Mod+V) only. ~210 cells ≈ the golden ratio of geekom's
      # 4K panel (0.61804 × 3840 ≈ 2354 px at ~11.2 px/cell for this font at
      # size 14); revisit this value first if a floated terminal looks wrong.
      window-width = 210;
      window-height = 40;
    };
  };

  # Per-user desktop state, split by `session` into chunks merged by mkMerge:
  # the GNOME session's keys (hplaptop) and the niri session's look keys
  # (geekom).
  #
  # mkMerge, not a second `dconf.settings` definition: the module system does not
  # deep-merge two separately-defined attrsets from the same module.
  #
  # `programs.dconf.enable` is true on both desktop hosts (the niri host sets it
  # explicitly; GNOME's module mkDefaults it). The dash-to-dock PACKAGE lives on
  # the NixOS side with the same gate as the dock keys below, because GNOME
  # Shell loads extensions from a system path Home Manager cannot reach — the
  # enable state stays per-user dconf, here.
  dconf.settings = lib.mkMerge [
    # Input sources are GNOME's per-user keyboard state; under niri the layout
    # comes from systemd-localed via the empty xkb block in
    # config/niri/config.kdl, so nothing is written there. Gated on the field
    # being PRESENT (not defaulted to "us"): a host without `keyboardLayout`
    # keeps its dconf byte-identical, since writing an explicit input source
    # that matches the platform default would still take ownership of a key
    # GNOME manages. `user` is threaded via extraSpecialArgs.
    (lib.mkIf (osConfig.local.desktop.session == "gnome" && user ? keyboardLayout) {
      "org/gnome/desktop/input-sources" = {
        sources = [
          (lib.hm.gvariant.mkTuple [
            "xkb"
            user.keyboardLayout
          ])
        ];
      };
    })
    # GNOME session (hplaptop) only: the daemon that fires these keys
    # (gnome-settings-daemon) ships with GNOME. The niri session binds the same
    # two launches directly (config/niri/config.kdl), so the muscle memory is
    # shared even though nothing reads these keys there.
    #
    # Launch keys: Super+Return → ghostty, Super+b → Brave, through the
    # media-keys schema like anything the "Custom Shortcuts" GUI writes.
    # Commands are bare binary names resolved through PATH, so a package bump
    # cannot strand the binding; neither combo collides with a GNOME default
    # (its terminal shortcut is Ctrl+Alt+T).
    #
    # Dash to Dock, keyed to the same gate as its package on the NixOS side.
    # `disabled-extensions = []` is deliberate: the Shell keys are a union (an
    # extension in BOTH lists is ENABLED), and the HM dconf module only writes
    # keys named here. Leaving it unset would let a GUI toggle-off survive a
    # rebuild and win here only by accident of that union; `[]` makes this
    # config the single source of truth. A rebuild that silently re-enables
    # something the user turned off is worse than the GUI toggle being inert.
    (lib.mkIf (osConfig.local.desktop.session == "gnome") {
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

      "org/gnome/shell" = {
        enabled-extensions = [ "dash-to-dock@micxgx.gmail.com" ];
        disabled-extensions = [ ];
      };

      # Hidden by default, revealed only on bottom-edge pressure: no reserved
      # band. Icon size picked live.
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
    })
    # niri session (geekom): only the look keys GTK apps read straight from
    # dconf — color scheme, accent, icons. Everything else the old full-variant
    # chunk wrote (GTK theme, wallpaper, screensaver, PaperWM) belonged to
    # GNOME Shell or to the dropped Catppuccin GTK theme; Noctalia owns the
    # chrome and the wallpaper.
    (lib.mkIf (osConfig.local.desktop.session == "niri") {
      "org/gnome/desktop/interface" = {
        # Covers every app that respects `color-scheme` (libadwaita + most GTK4).
        color-scheme = "prefer-dark";

        # Native accent color (GNOME 47+). There is no `mauve`; `purple` is the
        # closest to the session's mauve accent (#cba6f7). Read directly by
        # libadwaita, so it recolors selection, focus rings, switches and
        # buttons with no theme package involved.
        accent-color = "purple";

        # GTK4/libadwaita honor `icon-theme` (`GtkIconTheme` reads it in both).
        # The package is in gtk.nix.
        icon-theme = "Papirus-Dark";
      };
    })
  ];
}
