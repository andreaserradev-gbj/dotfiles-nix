{
  lib,
  osConfig,
  pkgs,
  ...
}:
# herdr — terminal workspace manager for coding agents (Phase 0 trial passed;
# promotion per doc/adopting-tools.md). Gate matches the other dev-only HM
# modules: hplaptop (local.dev.enable = false) evaluates this to the empty
# config and never sees the package or the two config assets below.
#
# The package is the upstream prebuilt (below), fetched from the release that
# the `herdr` entry in modules/home/tool-pins.json pins — that table, not a
# flake input, is the version of record. `nfb` (scripts/nfb.sh) bumps it and
# re-fetches the two vendored integration assets below in the same run
# (doc/herdr.md checklist). From-source fallback: re-add the `herdr` flake
# input, bind it in the function args and set `home.packages = [ herdr ];`.
let
  # Prebuilt-by-default: upstream's STATIC-PIE release binary (see
  # herdr-prebuilt.nix for why — the from-source build measures ~5 min on a
  # fast CI runner and recompiled on every run because runner stores don't
  # persist, even when the drv was byte-identical between PRs). The
  # vendored plugin/extension assets below are text in this repo — they
  # never depended on the source build.
  herdrPkg = pkgs.callPackage ./herdr-prebuilt.nix {
    system = pkgs.stdenv.hostPlatform.system;
  };
in
lib.mkIf osConfig.local.dev.enable {
  home.packages = [ herdrPkg ];

  # Config lives in config/herdr/config.toml (verbatim copy of the
  # trial-verified file — edit the asset, not a generator; there is none).
  # xdg.configFile makes ~/.config/herdr/config.toml a store symlink, so a
  # stray hand-edit or self-updater write fails loudly instead of drifting.
  # NOTE: a hand-placed copy from the Phase 0 trial lives at this path until
  # the first `nrs`; HM's backupFileExtension moves it to config.toml.backup.
  xdg.configFile."herdr/config.toml".source = ../../config/herdr/config.toml;

  # opencode integration plugin, vendored byte-for-byte from herdr's source
  # tree at the pinned tag (src/integration/assets/opencode/). Stored here —
  # not in opencode.nix — so the herdr↔opencode coupling stays greppable in
  # one place, and the plugin version always matches the herdr binary:
  # both ride the same flake input. Re-vendor on tag bump if
  # HERDR_INTEGRATION_VERSION changed (checklist in doc/herdr.md).
  xdg.configFile."opencode/plugins/herdr-agent-state.js".source =
    ../../config/opencode/plugins/herdr-agent-state.js;

  # omp integration extension, same vendoring story as the opencode plugin
  # above (src/integration/assets/omp/ at the pinned tag → config/omp/).
  # Deploys to ~/.omp/agent/extensions/herdr-omp-agent-state.ts — omp's
  # extension dir (PI_CODING_AGENT_DIR semantics: ~/.omp/agent, NOT
  # ~/.config/omp), which is why this is home.file while the opencode
  # plugin above is xdg.configFile. herdr offers `herdr integration install
  # omp` doing the same copy; the store symlink replaces that flow and
  # makes a stray hand-install fail loudly instead of drifting.
  #
  # The two assets carry INDEPENDENT version counters (v0.9.1: opencode
  # plugin = 12, omp extension = 10) — never diff one against the other,
  # only against the same-file asset at the new tag. Checklist in
  # doc/herdr.md covers both.
  home.file.".omp/agent/extensions/herdr-omp-agent-state.ts".source =
    ../../config/omp/herdr-omp-agent-state.ts;
}
