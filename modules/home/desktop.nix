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
      font-size = 12;

      # foot's `pad = "8x8"` spelled the way ghostty spells it.
      window-padding-x = 8;
      window-padding-y = 8;
    };
  };
}
