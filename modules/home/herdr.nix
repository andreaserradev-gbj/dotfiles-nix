{
  lib,
  osConfig,
  herdr,
  ...
}:
# herdr — terminal workspace manager for coding agents (Phase 0 trial passed;
# promotion per doc/adopting-tools.md). Gate matches the other dev-only HM
# modules: hplaptop (local.dev.enable = false) evaluates this to the empty
# config and never sees the package or the two config assets below.
lib.mkIf osConfig.local.dev.enable {
  home.packages = [ herdr ];

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
  #
  # The agent *skill* is deliberately NOT vendored: it is npx-managed like the
  # other skills in ~/.agents/skills (manual `npx skills add herdrdev/herdr
  # --skill herdr -g`; re-run per tag bump — see doc/herdr.md).
  xdg.configFile."opencode/plugins/herdr-agent-state.js".source =
    ../../config/opencode/plugins/herdr-agent-state.js;
}
