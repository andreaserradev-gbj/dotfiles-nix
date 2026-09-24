{
  lib,
  osConfig,
  pkgs,
  ...
}:
# herdr — terminal workspace manager for coding agents, adopted per
# doc/adopting-tools.md. Same gate as the other dev-only HM modules: hplaptop
# evaluates this to the empty config and never sees the package or the two
# config assets below.
#
# The version of record is the `herdr` entry in modules/home/tool-pins.json, not
# a flake input (there is none). `nfb` bumps it and re-fetches the vendored
# assets in the same run — checklist in doc/herdr.md. From-source fallback:
# re-add the `herdr` flake input, bind it in the function args and set
# `home.packages = [ herdr ];`.
let
  # Prebuilt: upstream's static-PIE release binary — modules/home/herdr-prebuilt.nix
  # says why. The vendored assets below are text in this repo and never depended
  # on the source build.
  herdrPkg = pkgs.callPackage ./herdr-prebuilt.nix {
    system = pkgs.stdenv.hostPlatform.system;
  };
in
lib.mkIf osConfig.local.dev.enable {
  home.packages = [ herdrPkg ];

  # Config is the repo asset config/herdr/config.toml, verbatim (edit the file,
  # not a generator — there is none). A store symlink, so a stray hand-edit or
  # self-updater write fails loudly instead of drifting.
  xdg.configFile."herdr/config.toml".source = ../../config/herdr/config.toml;

  # opencode integration plugin, vendored byte-for-byte from herdr's source tree
  # at the pinned tag. It lives here rather than in opencode.nix so the
  # herdr↔opencode coupling stays greppable in one place, and the plugin version
  # always matches the binary: both come from the same pin.
  xdg.configFile."opencode/plugins/herdr-agent-state.js".source =
    ../../config/opencode/plugins/herdr-agent-state.js;

  # omp integration extension, same vendoring story. It deploys to
  # ~/.omp/agent/extensions/ (omp's own extension directory, not ~/.config/omp),
  # which is why this is home.file while the plugin above is xdg.configFile. The
  # two assets carry INDEPENDENT version counters — never diff one against the
  # other; the re-vendor checklist is in doc/herdr.md.
  home.file.".omp/agent/extensions/herdr-omp-agent-state.ts".source =
    ../../config/omp/herdr-omp-agent-state.ts;
}
