# Double-click defaults for the niri session, in the user layer (HM) so they
# survive a future GNOME return; gated on the same NixOS option as
# features/niri/home.nix — hplaptop keeps GNOME's defaults and evaluates this
# file to nothing. Keys are MIME types, values desktop-file IDs: the
# direction mimeapps.list reads (key = type to open, value = app to open it
# with). The IDs match the packages added to the niri optionals in
# features/desktop/nixos.nix. Types beyond this exact list (heic, avi, …) get
# no default here: glib ignores `image/*`-style wildcards in
# [Default Applications], so those fall back to the mimeinfo.cache order —
# loupe and celluloid are typically the sole or first registrants anyway.
{
  lib,
  osConfig,
  ...
}:

let
  loupe = "org.gnome.Loupe.desktop";
  celluloid = "io.github.celluloid_player.Celluloid.desktop";
in
lib.mkIf osConfig.programs.niri.enable {
  xdg.mimeApps.enable = true;
  xdg.mimeApps.defaultApplications = {
    "image/png" = loupe;
    "image/jpeg" = loupe;
    "image/webp" = loupe;
    "image/gif" = loupe;
    "video/mp4" = celluloid;
    "video/webm" = celluloid;
    "video/x-matroska" = celluloid;
    "video/quicktime" = celluloid;
  };
}
