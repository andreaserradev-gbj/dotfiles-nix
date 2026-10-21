# Home-Manager half of the niri session seam: the two config files, verbatim
# from config/niri/ and config/noctalia/ (edit those files, not a generator —
# there is none).
#
# Gated on the NixOS option, not on a repo option: `programs.niri.enable` is
# the same switch that puts the niri session in GDM, so the config cannot exist
# for a session the host does not offer. hplaptop never sets it and evaluates
# this to the empty config.
{
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  # Each file is validated in its own derivation, so the check IS the deployed
  # artifact: no marker file, nothing to keep in sync. A broken asset fails the
  # rebuild, which matters because niri answers a bad config by falling back to
  # its built-in defaults (a session with no bar and no Noctalia) and Noctalia
  # silently ignores one it cannot parse. Unknown keys are warnings, not
  # errors, in both validators.
  checked =
    name: validate: src:
    pkgs.runCommand name { } ''
      ${validate} ${src}
      cp ${src} $out
    '';

  # The SAME niri the system runs, not `pkgs.niri`: the host may override the
  # package (geekom carries a patch into it), and validating with a different
  # build pulls a second niri into the closure — two niri binaries for one
  # session. The validator only needs the `validate` subcommand, so it works
  # with any build of the same version.
  niri = osConfig.programs.niri.package;
in
lib.mkIf osConfig.programs.niri.enable {
  xdg.configFile."niri/config.kdl".source =
    checked "niri-config.kdl" "${niri}/bin/niri validate -c"
      ../../config/niri/config.kdl;
  xdg.configFile."noctalia/config.toml".source =
    checked "noctalia-config.toml" "${pkgs.noctalia}/bin/noctalia config validate"
      ../../config/noctalia/config.toml;
}
