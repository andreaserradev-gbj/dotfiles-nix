# Home-Manager half of the desktop seam, gated on the SAME option as the
# NixOS half. `osConfig` is auto-injected because Home Manager runs as a NixOS
# module here, so this needs no extraSpecialArgs wiring in the flake.
#
# This ADDS ghostty. It does NOT replace foot. foot stays enabled on both
# hosts: it is the VM's login program (services.cage launches it directly) and
# geekom's fallback if a GPU-accelerated terminal ever misbehaves.
{ lib, osConfig, ... }:

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
  dconf.settings = {
    "org/gnome/shell" = {
      enabled-extensions = [ "paperwm@paperwm.github.com" ];
      disabled-extensions = [ ];
    };
  };
}
