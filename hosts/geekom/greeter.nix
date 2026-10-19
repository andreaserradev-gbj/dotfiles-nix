# The only path in: greetd + regreet on VT1, with regreet hosted INSIDE a
# minimal niri (not cage). Lives with this host like usb-mouse-recovery.nix —
# hplaptop keeps GDM and must not see greetd. The session option that dropped
# GDM lives in modules/nixos/desktop.nix.
#
# The command is a plain assignment on purpose: the regreet module sets its
# cage command with `mkDefault`, so a plain value replaces it with no
# conflict and no mkForce. The greeter's niri config is delivered through
# environment.etc — the greeter user has no home-manager home — and validated
# where it is built, same pattern as modules/home/niri.nix: the check IS the
# deployed artifact, so a broken config fails the rebuild instead of dropping
# the machine to a black screen.
{
  lib,
  pkgs,
  ...
}:

let
  checked =
    name: validate: src:
    pkgs.runCommand name { } ''
      ${validate} ${src}
      cp ${src} $out
    '';
in
{
  services.greetd.enable = true;
  programs.regreet.enable = true;

  # The greeter gets the theming the GDM login screen deliberately skipped
  # (modules/nixos/desktop.nix): Mocha + Papirus-Dark, the session's own look
  # (modules/home/gtk.nix). regreet is libadwaita, which ignores the GTK
  # theme name — the icons land, the dark flag does the rest. Judge the look
  # at first boot; extraCss is the fallback lever.
  programs.regreet.theme = {
    name = "catppuccin-mocha-mauve-standard";
    package = pkgs.catppuccin-gtk.override {
      variant = "mocha";
      accents = [ "mauve" ];
    };
  };
  programs.regreet.iconTheme = {
    name = "Papirus-Dark";
    package = pkgs.catppuccin-papirus-folders.override {
      flavor = "mocha";
      accent = "mauve";
    };
  };
  programs.regreet.settings.GTK.application_prefer_dark_theme = true;

  # Password auth — a daily workstation with sops secrets and SSH keys on
  # disk, not a kiosk (the VM's greetd uses `nullok` for exactly that
  # reason). No `initial_session`: nothing autologins.
  services.greetd.settings.default_session.command =
    "${lib.getExe pkgs.niri} -c /etc/niri/greeter.kdl -- ${lib.getExe pkgs.regreet}";

  environment.etc."niri/greeter.kdl".source =
    checked "niri-greeter.kdl" "${pkgs.niri}/bin/niri validate -c"
      ../../config/niri/greeter.kdl;
}
