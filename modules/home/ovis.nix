{
  lib,
  osConfig,
  pkgs,
  unstablePkgs,
  ...
}:
# ovis — the herdr web/phone client, adopted per doc/adopting-tools.md. Same gate
# as herdr.nix: hplaptop evaluates this to the empty config and never sees the
# package, the link step or the env asset.
#
# The version of record is the `ovis` entry in modules/home/tool-pins.json;
# scripts/nfb.sh bumps it together with the vendored manifest. doc/ovis.md
# carries the ownership table, the access model and the tailnet runbook.
let
  # bun from the UNSTABLE tree, not `pkgs`: pinned 26.05 ships 1.3.13 and
  # upstream's scripts/preflight.sh rejects 1.0–1.3, while unstable ships 1.4.2.
  # It is the interpreter the manifest's commands name by absolute path and the
  # one that builds the client, so a stable bun would be rejected at install time
  # and would build a client the preflight never blessed.
  #
  # Referenced INSIDE the dev gate, per the rule at the bottom of flake.nix: the
  # second tree must not be forced on a host that does not enable it, and
  # hplaptop's closure must not move.
  bun = unstablePkgs.bun;

  ovisPlugin = pkgs.callPackage ./ovis-prebuilt.nix {
    inherit bun;
    system = pkgs.stdenv.hostPlatform.system;
  };
in
lib.mkIf osConfig.local.dev.enable {
  # The plugin root, linked into herdr's registry by the activation below. Not a
  # `home.packages` entry: there is no binary to put on PATH, the artifact is the
  # directory itself.
  home.activation.linkHerdrOvis = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${
      pkgs.callPackage ./herdr-prebuilt.nix { system = pkgs.stdenv.hostPlatform.system; }
    }/bin/herdr plugin link ${ovisPlugin}
  '';

  # Non-secret settings, verbatim from the repo (config/ovis/env). A store
  # symlink into herdr's plugin config dir: Ovis reads `env` there before it
  # starts, and herdr keeps that directory outside Nix's ~/.config ownership.
  # Safe ONLY because the file holds no credential — /nix/store is 0444 and this
  # repo is public. A token, if ever wanted, takes the sops.templates route at
  # this same path with mode 0400, replacing this symlink (doc/ovis.md).
  xdg.configFile."herdr/plugins/config/devswha.ovis/env".source = ../../config/ovis/env;
}
