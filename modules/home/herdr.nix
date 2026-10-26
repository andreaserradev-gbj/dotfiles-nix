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

  # reviewr plugin (persiyanov/herdr-reviewr): FOD tarball + vendored manifest
  # assembled into a store directory. Ownership is by reference, not copy:
  # `herdr plugin link` points the user's plugin registry at this immutable
  # path; it is idempotent across switches and re-points itself when a bump
  # changes the path, so no uninstall/install churn is needed. The plugin runs
  # with full user privileges — the pin and the vendored manifest are the
  # review surface, same trust shape as herdr-prebuilt above.
  herdrReviewrPlugin = pkgs.callPackage ./herdr-reviewr-prebuilt.nix {
    system = pkgs.stdenv.hostPlatform.system;
    manifestSrc = ../../config/herdr/plugins/reviewr-herdr-plugin.toml;
  };
in
lib.mkIf osConfig.local.dev.enable {
  home.packages = [ herdrPkg ];

  # Config is the repo asset config/herdr/config.toml, verbatim (edit the file,
  # not a generator — there is none). A store symlink, so a stray hand-edit or
  # self-updater write fails loudly instead of drifting.
  xdg.configFile."herdr/config.toml".source = ../../config/herdr/config.toml;

  # omp integration extension, vendored byte-for-byte from herdr's source tree
  # at the pinned tag. It deploys to ~/.omp/agent/extensions/ (omp's own
  # extension directory, not ~/.config/omp), which is why this is home.file
  # while herdr's own config above is xdg.configFile. The re-vendor checklist
  # is in doc/herdr.md.
  home.file.".omp/agent/extensions/herdr-omp-agent-state.ts".source =
    ../../config/omp/herdr-omp-agent-state.ts;

  # Runs on every switch; with no server running it still registers (plugin
  # link needs only the user's registry). A link failure must fail the switch:
  # pin, manifest and binary are then out of agreement.
  home.activation.linkHerdrReviewr = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${herdrPkg}/bin/herdr plugin link ${herdrReviewrPlugin}
  '';

  # The server as a systemd USER unit. Linger (geekom's host file) keeps the
  # user manager alive at boot — see the linger comment there for the why.
  systemd.user.services.herdr = {
    Unit = {
      Description = "herdr background server";
      StartLimitIntervalSec = 60;
      StartLimitBurst = 3;
    };
    Service = {
      # exec, not forking: `herdr server` stays in the foreground, so a
      # forking unit would report a dead MainPID.
      Type = "exec";
      # Two servers cannot share one socket: without the guard, a
      # terminal-launched server makes the unit exit 1 and on-failure retries
      # into failed/start-limit-hit. String match — `herdr status server`
      # exits 0 in both states; an exit-1 skip is inactive, not failed.
      # ExecCondition belongs in [Service]: ignored silently in [Unit].
      ExecCondition = "/bin/sh -c '! ${herdrPkg}/bin/herdr status server | grep -q \"^status: running\"'";
      ExecStart = "${herdrPkg}/bin/herdr server";
      Restart = "on-failure";
      RestartSec = 5;
    };
    # default.target, not graphical-session.target: the server must exist
    # without a session.
    Install.WantedBy = [ "default.target" ];
  };
  # No HERDR_STARTUP_CWD: a client attach to a workspace-less server creates
  # the workspace itself (cwd $HOME) — exactly what happens at boot.
}
