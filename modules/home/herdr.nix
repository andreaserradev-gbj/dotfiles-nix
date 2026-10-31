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

  # The server as a systemd USER unit, plus a waiter that is what actually
  # makes its environment correct. Both together are the fix; either alone is
  # not. doc/herdr.md ("The unit") carries the incident and the measurements.
  #
  # The invariant: the server's environment is inherited by every pane and every
  # agent, and is fixed at exec. If it starts before the session environment is
  # imported, every restored pane's agent runs without WAYLAND_DISPLAY and all
  # clipboard tools fail. Binding the unit to default.target (boot) guaranteed
  # that failure; binding it to graphical-session.target is necessary but NOT
  # sufficient, because niri sets WAYLAND_DISPLAY itself and imports it a
  # fraction of a second after that target is reached. Hence the waiter.
  #
  # graphical-session.target does not exist on a host without a session (the
  # VM's cage kiosk starts none), so those hosts keep the boot target: there is
  # no session import to race and panes inherit cage's own environment.
  systemd.user.services =
    let
      # WAITER, and the reason it exists: `WantedBy=graphical-session.target` does
      # NOT mean the session environment is present when the server starts. niri
      # SETS `WAYLAND_DISPLAY` itself (naming the socket it creates) and imports it
      # into the user manager a fraction of a second AFTER the target is reached —
      # measured: target at 07:48:18.19, the unit's condition at 07:48:17.76 saw no
      # variable and skipped the start, so no server came up. Home Manager's
      # sd-switch is the other half: it starts new units explicitly without
      # consulting their target at all.
      #
      # The wait cannot live inside the herdr unit: a process inherits its
      # environment at exec, so polling `$WAYLAND_DISPLAY` from ExecCondition or
      # ExecStartPre keeps reading the copy it was born with (measured: a unit
      # started with the variable absent still saw it absent after the manager
      # imported it 0.5 s later). Only a process that waits and THEN asks the
      # manager to start the server gets the imported value — which is this unit.
      #
      # Desktop hosts only: the VM's cage kiosk imports nothing into the user
      # manager, so the poll there could only ever time out; its herdr keeps
      # starting on default.target as before.
      sessionEnvWait = {
        Unit = {
          Description = "Wait for the graphical session environment";
          # herdr names this unit in Requires+After, so systemd starts the
          # server only once this oneshot has finished. Do NOT instead give this
          # unit `Before=herdr.service`: herdr is WantedBy the target this unit
          # is also WantedBy, so both would belong to that target's transaction
          # and systemd resolves the resulting loop
          # (target -> waiter -> herdr -> target) by DELETING herdr's start job
          # (measured 08:02:05). Ordering via herdr's own Requires is the same
          # guarantee without closing a cycle.
          #
          # And do NOT rely on two independent WantedBy units: measured
          # 08:14:29, herdr and the waiter started in PARALLEL, herdr won by
          # 0.4 s, and its `systemctl start` from the waiter was a no-op because
          # the unit was already active — so the server kept the pre-import
          # environment and every clipboard tool was dead again (server pid 2665,
          # no WAYLAND_DISPLAY, while the waiter had already exited 0).
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Poll the manager (the only place the imported value appears) every
          # 200 ms for up to 10 s. `break` rather than `exit` so the unit records
          # success either way: on timeout herdr still starts, with whatever
          # environment exists (on a host with no session that is the old
          # behaviour, and its own socket guard decides the rest). A `failed`
          # waiter would take herdr down with it through the Requires edge.
          ExecStart = "/bin/sh -c 'for i in $(seq 50); do systemctl --user show-environment | grep -q \"^WAYLAND_DISPLAY=\" && break; sleep 0.2; done'";
        };
        # NOT WantedBy the target: being in the same transaction as herdr is
        # what closes the loop. herdr's Wants+After above is the only edge, with
        # graphical-session.target reaching herdr, herdr reaching this unit —
        # one direction, no cycle (verified: the unit start job survives).
        Install.WantedBy = [ "herdr.service" ];
      };
    in
    {
      herdr = {
        Unit = {
          Description = "herdr background server";
          StartLimitIntervalSec = 60;
          StartLimitBurst = 3;
        }
        # Ordering that actually holds: the server cannot start until the
        # waiter has seen the session environment. Conditional (Wants) rather
        # than hard (Requires) so the VM, which has no waiter unit at all, still
        # starts herdr normally; `After` is what makes the wait effective.
        // lib.optionalAttrs osConfig.local.desktop.enable {
          Wants = [ "herdr-session-env.service" ];
          After = [ "herdr-session-env.service" ];
        };
        Service = {
          # exec, not forking: `herdr server` stays in the foreground, so a
          # forking unit would report a dead MainPID.
          Type = "exec";
          # Two servers cannot share one socket: without the guard, a
          # terminal-launched server makes the unit exit 1 and on-failure retries
          # into failed/start-limit-hit. String match — `herdr status server`
          # exits 0 in both states. ExecCondition belongs in [Service]; in [Unit]
          # it is silently ignored.
          ExecCondition = "/bin/sh -c '! ${herdrPkg}/bin/herdr status server | grep -q \"^status: running\"'";
          ExecStart = "${herdrPkg}/bin/herdr server";
          Restart = "on-failure";
          RestartSec = 5;
        };
        # Keyed on the same seam that decides whether a graphical session exists:
        # geekom (niri) gets a session-scoped server, the VM's cage kiosk — which
        # starts no such target — keeps the boot one. See the block above.
        Install.WantedBy =
          lib.optionals (!osConfig.local.desktop.enable) [ "default.target" ]
          ++ lib.optionals osConfig.local.desktop.enable [ "graphical-session.target" ];
      };
    }
    // lib.optionalAttrs osConfig.local.desktop.enable {
      herdr-session-env = sessionEnvWait;
    };
  # No HERDR_STARTUP_CWD: a client attach to a workspace-less server creates
  # the workspace itself (cwd $HOME) — the case on the VM, where the boot
  # target has the server up before anyone attaches.
}
