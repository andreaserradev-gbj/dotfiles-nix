# Double-click defaults for the niri session, in the user layer (HM) so they
# survive a future GNOME return; gated on the same NixOS option as
# modules/home/niri.nix — hplaptop keeps GNOME's defaults and evaluates this
# file to nothing. The desktop-file IDs match the packages added to the niri
# optionals in modules/nixos/desktop.nix. The catch-alls lean on glib's
# wildcard support in mimeapps.list; without them an unlisted container
# (heic, mkv, avi) would fall back to Brave.
{
  lib,
  osConfig,
  ...
}:

lib.mkIf osConfig.programs.niri.enable {
  xdg.mimeApps.enable = true;
  xdg.mimeApps.defaultApplications = {
    "org.gnome.Loupe.desktop" = [
      "image/png"
      "image/jpeg"
      "image/webp"
      "image/gif"
      "image/*"
    ];
    "io.github.celluloid_player.Celluloid.desktop" = [
      "video/mp4"
      "video/webm"
      "video/x-matroska"
      "video/quicktime"
      "video/*"
    ];
  };
}
