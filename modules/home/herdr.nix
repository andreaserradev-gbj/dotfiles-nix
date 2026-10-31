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

  # The server as a systemd USER unit.
  #
  # THE INVARIANT: the server's environment is inherited by every pane and every
  # agent, and it is fixed when the server execs. If it starts before the session
  # environment is imported, every restored pane's agent runs without the
  # session variables and all clipboard tools fail (doc/herdr.md, "The unit").
  #
  # `WantedBy=graphical-session.target` is necessary but NOT sufficient: niri
  # imports its variables into the user manager in stages, around the moment the
  # target is reached. So on a desktop host the unit does not exec herdr
  # directly; ExecStart waits for the manager to have the variables and then
  # execs the server with them.
  #
  # One unit, not two, and that is deliberate. A separate waiter has to be
  # ordered against this one, and every ordering tried here closed a cycle with
  # the target's transaction (target -> herdr -> waiter -> target), which systemd
  # resolves by DELETING herdr's start job. Waiting inside the one unit has no
  # second edge to cycle through.
  #
  # A child CAN be given an environment its parent lacks; that is why the wait
  # lives in ExecStart and not in ExecCondition or ExecStartPre — those read
  # only the copy the process was born with. The measurements and the failed
  # shapes are in doc/herdr.md ("The unit"); they live there, not here.
  systemd.user.services =
    let
      # The wait lives in a SCRIPT, not an inline `sh -c`: nested quoting in a
      # systemd ExecStart is where the first attempts broke (a stray quote made
      # the poll a no-op silently), and a store script is testable on its own.
      #
      # It polls the user manager — the only place the imported values appear —
      # for WAYLAND_DISPLAY and NIRI_SOCKET, then execs the server with them.
      # WAYLAND_DISPLAY alone is not enough: niri imports in stages, and a
      # server exec'd between the stages runs without NIRI_SOCKET, so `niri msg`
      # is dead in every pane for the server's whole life. DISPLAY (Xwayland,
      # spawned on demand) is deliberately not awaited: it may never appear.
      #
      # After the timeout the server starts anyway, with whatever environment
      # exists — a missing server is worse, and the ExecCondition above still
      # keeps pre-login starts off.
      herdrStart = pkgs.writeTextFile {
        name = "herdr-start";
        executable = true;
        destination = "/bin/herdr-start";
        text = ''
          #!${pkgs.runtimeShell}
          set -eu
          mgr=""
          w=""
          n=""
          for _ in $(seq 50); do
            mgr=$(systemctl --user show-environment 2>/dev/null || true)
            w=$(printf '%s\n' "$mgr" | grep -E '^WAYLAND_DISPLAY=' || true)
            n=$(printf '%s\n' "$mgr" | grep -E '^NIRI_SOCKET=' || true)
            [ -n "$w" ] && [ -n "$n" ] && break
            sleep 0.2
          done
          [ -n "$w" ] && export "$w"
          [ -n "$n" ] && export "$n"
          exec ${herdrPkg}/bin/herdr server
        '';
      };
    in
    {
      herdr = {
        Unit = {
          Description = "herdr background server";
          StartLimitIntervalSec = 60;
          StartLimitBurst = 3;
        };
        Service = {
          # exec, not forking: the server stays in the foreground, so a forking
          # unit would report a dead MainPID. herdrStart ends in `exec`, so the
          # server is still the unit's main process.
          Type = "exec";
          # Two servers cannot share one socket: without the guard, a
          # terminal-launched server makes the unit exit 1 and on-failure retries
          # into failed/start-limit-hit. String match — `herdr status server`
          # exits 0 in both states. ExecCondition belongs in [Service]; in [Unit]
          # it is silently ignored.
          ExecCondition =
            "/bin/sh -c '! ${herdrPkg}/bin/herdr status server | grep -q \"^status: running\"'"
            + lib.optionalString osConfig.local.desktop.enable " && test -n \"$WAYLAND_DISPLAY\"";
          ExecStart =
            if osConfig.local.desktop.enable then
              "${herdrStart}/bin/herdr-start"
            else
              "${herdrPkg}/bin/herdr server";
          Restart = "on-failure";
          RestartSec = 5;
        };
        # Keyed on the same seam that decides whether a graphical session exists:
        # geekom (niri) gets a session-scoped server, the VM's cage kiosk — which
        # starts no such target — keeps the boot one. There is no session import
        # to race there, and panes inherit cage's own environment.
        Install.WantedBy =
          lib.optionals (!osConfig.local.desktop.enable) [ "default.target" ]
          ++ lib.optionals osConfig.local.desktop.enable [ "graphical-session.target" ];
      };
    };
  # No HERDR_STARTUP_CWD: a client attach to a workspace-less server creates
  # the workspace itself (cwd $HOME) — the case on the VM, where the boot
  # target has the server up before anyone attaches.
}
