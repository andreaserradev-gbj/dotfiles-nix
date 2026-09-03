# Home-Manager half of the desktop seam, gated on the SAME option as the
# NixOS half. `osConfig` is auto-injected because Home Manager runs as a NixOS
# module here, so this needs no extraSpecialArgs wiring in the flake.
#
# This ADDS ghostty. It does NOT replace foot. foot stays enabled on both
# hosts: it is the VM's login program (services.cage launches it directly) and
# geekom's fallback if a GPU-accelerated terminal ever misbehaves.
#
# ghostty is gated on `desktop.enable` ALONE: a `vanilla` host (hplaptop) still
# wants a terminal. The dconf.settings block (PaperWM, Catppuccin theme,
# wallpaper, accent, text-scaling, scaling-factor) is gated on
# `desktop.enable && variant == "full"` — a `vanilla` host gets plain GNOME with
# no theming. Default `"full"` keeps geekom themed — originally chosen to hold
# geekom's drvPath still, though hash stability is no longer a goal in itself
# (see home.nix).
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
      # Catppuccin Mocha ships built into ghostty, so unlike foot.nix this
      # needs no hand-transcribed palette — but the intent is identical: both
      # terminals must look the same as each other and as the Mac.
      theme = "Catppuccin Mocha";

      font-family = "JetBrainsMono Nerd Font";
      font-size = 14;

      # foot's `pad = "8x8"` spelled the way ghostty spells it.
      window-padding-x = 8;
      window-padding-y = 8;

      # No decorations at all: no GTK headerbar (the title/close "caption"),
      # no borders. Two reasons, one aesthetic and one mechanical:
      #
      #   - PaperWM already marks the focused window (selection-border-size /
      #     selection-border-radius are set in the user's dconf), so a titlebar
      #     adds nothing but chrome under a tiling WM.
      #
      #   - `window-width` below is only EXACT with decorations off. Ghostty's
      #     own docs: on GTK the calculated grid size does not account for
      #     window decorations, so with a titlebar present the mapping from
      #     grid cells to pixels drifts by the headerbar height. `none` makes
      #     `window-width` map 1:1 to pixels.
      #
      # `gtk-titlebar` is NOT set: it only matters when decorations exist
      # (nothing when `window-decoration` is `none`), so setting it would be
      # dead config. `auto` (the default) is skipped deliberately too — on
      # GNOME it resolves to client-side decorations, i.e. the headerbar we
      # are removing.
      window-decoration = "none";

      # Initial window size, in terminal grid cells — ghostty requires BOTH
      # keys set or it ignores the pair entirely (one alone does nothing).
      #
      # PaperWM, not ghostty, is why these values matter: when a window maps,
      # PaperWM's Space.layout adopts the window's current frame width for
      # its column (tiling.js: `tiledWidth ?? frame.width`) and never re-pins
      # it afterwards — so the terminal opens tiled at exactly this width and
      # Super+R (`cycle-width`) still cycles freely. The alternative was a
      # PaperWM winprop with `preferredWidth`, which is REJECTED on purpose:
      # a winprop re-applies its width on every relayout, so any window
      # opening/closing would snap the terminal back and undo the user's
      # Super+R choice.
      #
      # window-height is a placeholder satisfying the both-keys rule: PaperWM
      # forces tiled windows to full workarea height anyway.
      #
      # 210 cells ≈ the third `cycle-width-steps` ratio (0.61804, the golden
      # ratio) of geekom's 4K panel minus PaperWM margins/gap
      # (0.61804 × (3840 − 2×16 − 16) ≈ 2354 px), at ~11.2 px/cell for
      # JetBrainsMono Nerd Font at 14. If ghostty honors GNOME's
      # `text-scaling-factor = 1.25` (desktop.nix, dconf) the correct value
      # is ~168 instead — decided by eye after the first rebuild, not by
      # speculation, and 210 is the value to revisit first if the opened
      # width misses the third Super+R step.
      window-width = 210;
      window-height = 40;
    };
  };

  # PaperWM enable state + Catppuccin theming. Gated on `variant == "full"`
  # INSIDE the `desktop.enable` block: a `vanilla` host (hplaptop) gets plain
  # GNOME with no PaperWM and no theming. Default `"full"` keeps geekom
  # identical.
  #
  # The extension PACKAGE is installed on the NixOS side (modules/nixos/desktop.nix)
  # because GNOME Shell loads extensions from a system path Home Manager
  # cannot reach. The ENABLE state, however, is per-user dconf under
  # org.gnome.shell, so it belongs HERE.
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
  #
  # mkMerge, not a second attribute definition: the module system does not
  # deep-merge two separately-defined `dconf.settings` attrsets from the same
  # module (that eval error is why this block exists in this shape).
  dconf.settings = lib.mkMerge [
    # Gated on the field being PRESENT (not defaulted to "us"): hosts without
    # `keyboardLayout` keep their dconf byte-identical — writing an explicit
    # input source that matches the platform default would still move the
    # derivation and take ownership of a key GNOME currently manages.
    # `user` is the per-host identity attrset threaded via extraSpecialArgs.
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
    # Launch keybindings: Super+Return → ghostty, Super+b → Brave. GNOME has no
    # declarative module for these, so they go through the media-keys custom
    # keybindings schema like everything the "Custom Shortcuts" GUI writes —
    # dconf is per-user state and this file already owns the user's dconf for
    # the GNOME desktop.
    #
    # Gated on `desktop.enable` ONLY (not the "full" variant): both vanilla and
    # full hosts want the same two launches, and both have ghostty and Brave in
    # their profiles — ghostty via this same module, Brave via the NixOS half.
    # Commands are bare binary names, resolved through PATH, so no store path
    # is baked in and a package bump cannot strand the binding.
    #
    # `binding` is GNOME's accelerator syntax: `<Super>` is the mod4 modifier,
    # `Return` is the Return keysym. `<Super>Return` does not collide with any
    # GNOME default (the built-in terminal shortcut is Ctrl+Alt+T), nor with
    # any PaperWM default (checked against the schema shipped in
    # gnome-shell-extension-paperwm-148; `<Super>b` only matched
    # bracketleft/bracketright there, nothing binds the b keysym). It DOES
    # collide with PaperWM's `new-window` default (['<Super>Return',
    # '<Super>n']), but that default is explicitly trimmed in the full-variant
    # block below — Shell grab-order would otherwise give PaperWM the combo
    # and the ghostty binding would never fire on geekom.
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
    (lib.mkIf (osConfig.local.desktop.variant == "full") {
      "org/gnome/shell" = {
        enabled-extensions = [ "paperwm@paperwm.github.com" ];
        disabled-extensions = [ ];
      };

      # PaperWM's `new-window` action defaults to ['<Super>Return', '<Super>n'],
      # which collides with the custom0 terminal binding above. PaperWM
      # proactively grabs conflicting combos on enable (overrideConflicts), and
      # Shell grabs beat gsd media-keys, so Super+Return would duplicate the
      # focused window instead of launching ghostty. Trim the default to just
      # '<Super>n' so the media-keys binding owns Super+Return on the full
      # host; vanilla hosts skip PaperWM entirely and never see this key.
      "org/gnome/shell/extensions/paperwm/keybindings" = {
        new-window = [ "<Super>n" ];
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

        # Scales fonts only; XWayland root window stays at native 3840×2160,
        # so games keep seeing the real panel even with this raised. Picked
        # over `scaling-factor` (integer-only, rescales the whole output) for
        # the same reason the desktop runs at 100%: fractional scaling on the
        # output inflates XWayland's root window to 7680×4320 and games render
        # four times the pixels. text-scaling-factor touches neither.
        text-scaling-factor = 1.25;

        # Pin the OUTPUT scale to 1:1 (100%). GNOME's per-display auto-default
        # picks fractional values like 125% on a 4K panel at first login, which
        # inflates XWayland's root window (ceil to integer 2×) and makes games
        # render at 7680×4320. This locks it to integer 1 so the desktop output
        # matches the panel natively and XWayland reports the real resolution.
        scaling-factor = lib.gvariant.mkUint32 1;

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
    })
  ];
}
