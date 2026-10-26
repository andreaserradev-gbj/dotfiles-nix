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
  # bun from the UNSTABLE tree, not `pkgs`: pinned stable is below the floor
  # upstream's scripts/preflight.sh enforces, and unstable is above it. It is the
  # interpreter the manifest's commands name by absolute path and the one that
  # builds the client, so a stable bun would be rejected at install time. The
  # floor and the two trees are in doc/ovis.md, "bun comes from nixpkgs-unstable".
  #
  # Referenced only from inside the dev gate, per the rule at the bottom of
  # flake.nix; the binding sits in the module `let` because an option body cannot
  # introduce one, and stays unforced on a host that never enables the gate.
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

  # Non-secret settings, verbatim from the repo (config/ovis/env), symlinked into
  # herdr's plugin config dir — Ovis reads `env` there before it starts, and herdr
  # keeps that directory outside Nix's ~/.config ownership. No credential may
  # live there; doc/ovis.md, "Configuration surfaces", says why and what a token
  # would take instead.
  xdg.configFile."herdr/plugins/config/devswha.ovis/env".source = ../../config/ovis/env;
}
