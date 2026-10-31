# herdr — terminal workspace manager for coding agents

herdr ([github:herdrdev/herdr](https://github.com/herdrdev/herdr)) is a
terminal workspace manager built around AI coding agents: panes and tabs like
zellij, plus an agent registry that tracks which agent (omp, claude, codex, …)
runs in which pane. It was promoted into the flake as a dev-gated home-layer
tool via the [adoption ladder](adopting-tools.md).

**Status: adopted, coexisting with zellij.** Both are installed on dev hosts
(`vm`, `geekom`); zellij's retirement is a separate later PR. The adoption keeps
**one module per role** — zellij's role (multiplexer) and herdr's role (agent
workspace) overlap enough to coexist but not to merge; herdr's agent registry is
the differentiator, and plain pane management is unchanged muscle memory. Don't
nest one inside the other: both claim `alt+hjkl`, and the inner manager's keys
win in ways that are hard to reason about — run them in separate terminals.

## Ownership: Nix-managed vs manual/stateful

[modules/home/herdr.nix](../modules/home/herdr.nix) wraps its whole body in
`lib.mkIf osConfig.local.dev.enable`, like zellij; `hplaptop` (dev off)
evaluates it to the empty config.

| artifact | owned by | how it gets there |
|---|---|---|
| herdr binary | Nix | upstream's prebuilt release FOD ([herdr-prebuilt.nix](../modules/home/herdr-prebuilt.nix), called with `callPackage` — no host carries a `herdr` arg) → `home.packages`, dev-gated; version + both hashes from the `herdr` entry in [tool-pins.json](../modules/home/tool-pins.json) |
| `~/.config/herdr/config.toml` | Nix | `xdg.configFile` from the verbatim asset [config/herdr/config.toml](../config/herdr/config.toml) |
| `~/.omp/agent/extensions/herdr-omp-agent-state.ts` | Nix | `home.file` from the vendored byte-for-byte copy [config/omp/herdr-omp-agent-state.ts](../config/omp/herdr-omp-agent-state.ts) — omp's base directory is `~/.omp/agent/`, not `~/.config/omp/` |
| agent skill (`~/.agents/skills/herdr/SKILL.md`) | **npx, manual** | `npx skills add herdrdev/herdr --skill herdr -g` |
| reviewr plugin (`persiyanov.reviewr`, `~/.config/herdr/plugins`) | Nix | musl release tarball + vendored manifest [reviewr-herdr-plugin.toml](../config/herdr/plugins/reviewr-herdr-plugin.toml) assembled by [herdr-reviewr-prebuilt.nix](../modules/home/herdr-reviewr-prebuilt.nix) into a store dir; `home.activation` in [herdr.nix](../modules/home/herdr.nix) runs `herdr plugin link` on it every switch |
| ovis plugin (`devswha.ovis`, `~/.config/herdr/plugins`) | Nix | built from the pinned tag by [ovis-prebuilt.nix](../modules/home/ovis-prebuilt.nix) (no server asset is released, so this one is not a prebuilt FOD); `home.activation` in [ovis.nix](../modules/home/ovis.nix) links it, dev-gated. Ownership, the access model and the tailnet runbook: [ovis.md](ovis.md) |
| `~/.config/systemd/user/herdr.service` | Nix | user unit from [herdr.nix](../modules/home/herdr.nix) (dev-gated), pulled in by `graphical-session.target` so panes inherit the session environment — see "The unit" below |

The agent extension is deployed by [modules/home/herdr.nix](../modules/home/herdr.nix),
**not** by omp.nix: the herdr↔agent coupling stays in one
greppable place, and the single `nfb` run re-fetches it from the same release
tag as the binary, so they cannot drift apart. Vendoring pins it to a reviewed,
version-matched copy and makes a stray install (`herdr integration install omp`
offering to write its own copy) fail loudly instead of drifting silently. It
carries a version counter (the `HERDR_INTEGRATION_VERSION` marker at the top
of the file) and is diffed only against the same-file asset at the new tag.
The skill is deliberately *not* vendored: npx-managed like the other skills,
it stays editable/fresh without a rebuild and is re-run manually per bump.

## The config asset

Assets are verbatim — edit the asset, not a generator (there is none).

- `onboarding = false` — top-level boolean, not a table.
- `[theme] name = "catppuccin"` — canonical name (`catppuccin-mocha` is an alias).
- `[update]` holds herdr's **two** phone-home knobs, both curl-based:
  `version_check = false` (it only announces a version this install cannot take)
  and `manifest_check` **left on by design** — it refreshes the agent-detection
  manifests, and the agent registry is the reason this tool is here; the asset
  carries that reason next to the keys. Measured: a strace of the client
  with `version_check = false` shows the manifest fetch as the only outbound
  traffic. herdr *does* ship a self-updater (`herdr update`, channel set) but it
  is inert under Nix — on a store binary it refuses with "self-update is disabled
  for Nix installs", and there is no "disable self-updater" setting to make.

**Keymap.** Every binding is array-form, desktop entries first: each focus
binding carries a herdr prefix chord and a bare single, and every built-in
action ends with a prefix-mode alternate (`prefix+h/j/k/l` pane focus, `prefix+v` /
`prefix+minus` splits, `prefix+z` zoom, `prefix+c` new tab, `prefix+n`/`prefix+p`
tab switching) — the whole set mirrors zellij's navigation
([config/zellij/config.kdl](../config/zellij/config.kdl); the asset is the source
of truth for the list). The alternates are herdr's own defaults re-declared, not
invented — a configured list **replaces** that action's default, so the desktop
entries must stay — and they exist for keyboards with no Alt and no arrows (the
phone over SSH). `prefix+d` is deliberately not among them: reviewr owns it
below. The bare singles are **arrows**, not `alt+hjkl`: neovim
claims `alt+h` (toggle-hidden in grep/fzf pickers), and any bare alt-letter here
swallows it before it reaches the pane. Arrows leave hjkl to the app inside the
pane, and zellij already trains the Alt-arrow habit. Two upstream gaps worth
knowing: there is **no quit key** (`prefix+q` *detaches* — the server keeps
running; killing it is a CLI action), and wider zellij-mirror bindings were
deliberately left out of the asset — extend it after testing, don't ship
unverified keymap claims. Plugin actions bind as `[[keys.command]]` with
`type = "plugin_action"` and the qualified `plugin.id.action`; reviewr's toggle
lives on `prefix+d` (`prefix+r` is resize_mode, and bare alt-letters would
swallow keys inside panes). `herdr config check` validates the asset and is a real gate, not a formality:
a bad binding is reported and disabled (`invalid keybinding: … disabling
binding`), a bogus key prints `unknown config key …; ignoring key`, and the
exit is 1 either way (negative control measured on a throwaway copy via
`HERDR_CONFIG_PATH`).

## The unit

The server is a systemd **user** unit ([modules/home/herdr.nix](../modules/home/herdr.nix)),
`WantedBy=graphical-session.target`: its normal start is at login, with the
session. That ordering is the whole point — see below.

`WantedBy` is **not** what enforces it, and trusting it alone is the trap this
section exists to prevent. Three separate facts break the naive reading, all
measured on 2026-10-31:

1. **The target is reached before the environment exists.** `niri` *sets*
   `WAYLAND_DISPLAY` — it names the socket it creates — and imports it into the
   user manager a fraction of a second **after** `graphical-session.target` goes
   active. The unit's condition ran at 07:48:17.76 and saw no variable; the
   target was reached at 07:48:18.19.
2. **Home Manager starts new units itself.** Its activation calls `sd-switch`,
   which starts every new unit explicitly (`Starting units: herdr.service` in
   the journal) without consulting the target. Measured: a unit whose
   `WantedBy` target does not exist is still started. So every `nrs` hands the
   server a pre-import environment.
3. **The boot activation lags a generation.** It still carries the previous
   generation's `default.target.wants` link, so the first boot after a change
   starts the server at `Reached target Main User Target` — measured 07:34:27,
   ~70 s before login.

The repair is inside the one unit: on a desktop host its `ExecStart` is not the
binary but a small store script ([herdr.nix](../modules/home/herdr.nix),
`herdrStart`) that polls `systemctl --user show-environment` every 200 ms for up
to 10 s, for `WAYLAND_DISPLAY` and `NIRI_SOCKET` together, and then **`exec`s
the server with the values it read**. The child gets an environment its parent
never had, which is the only way this can work — polling
`$WAYLAND_DISPLAY` from `ExecCondition` or `ExecStartPre` reads just the copy the
process was born with (measured: a unit started without the variable still saw it
absent after the manager imported it 0.5 s later). On timeout the server starts
anyway — the `ExecCondition` gate below is what keeps a pre-login start from
being that timeout case.

Three shapes were tried and abandoned before this one, and each failure is worth
knowing because they all look reasonable:

| shape | outcome |
|---|---|
| both units `WantedBy` the target | started in **parallel**; herdr won by 0.4 s, and the waiter's later `systemctl start` was a no-op on an active unit (08:14) |
| `Before=herdr.service` on the waiter | ordering cycle `target → waiter → herdr → target`; systemd **deleted herdr's start job** (08:02) |
| `Wants`/`After` on herdr, waiter still `WantedBy` the target | same cycle, reached from the other side; start job deleted again (08:20) |

One unit has no second edge to cycle through, so none of those can recur. Do not
re-introduce a second unit for this; if the wait ever has to move, it moves into
the same `ExecStart`.

The `ExecCondition` therefore also requires `WAYLAND_DISPLAY` on a desktop host.
That is not redundant with the script: Home Manager's activation runs `sd-switch`,
which starts new units itself (`Starting units: herdr.service`), so at boot the
script would poll, time out after 10 s, and start the server without the value —
the same failure by a slower route. Skipping instead leaves the unit `inactive`
and the session target starts it later, once the import has landed.

First boot carrying all of this (2026-10-31 15:16:58, geekom): niri and the
unit-started server both exec'd inside the same second, and the server's
`/proc/<pid>/environ` showed `WAYLAND_DISPLAY` — the reboot confirmation #81
deferred. The same boot exposed the staged-import window above: the server had
no `NIRI_SOCKET` or `DISPLAY`, which the manager gained moments later, and
panes inherit the server's environment for its whole life. That measurement is
why the poll waits for `NIRI_SOCKET` too.

The herdr unit **yields instead of failing**: `ExecCondition` skips the start
when another server already owns the socket (a terminal-launched one, say),
taking the unit to `inactive` — never `failed`, no restart loop. The socket
guard must string-match `status: running`, because `herdr status server` exits 0
in both states. **This is why `systemctl --user is-active herdr` reads
`inactive` while the stack works**: a server you launched from a pane owns the
socket, so the unit yields and never runs as a unit at all. Check
`herdr status server` or `pgrep -f 'herdr server'`, not the unit.

The manual restart is `systemctl --user restart herdr.service` — mind the
restart cost under [Operational gotchas](#operational-gotchas) first. It is also
the recovery move when a server is found running without a session environment:
restart it once the session is up, and it re-inherits the manager's environment.

### Why the session target, and why it must stay that way

The server's environment is inherited by **every pane and every agent**, and it
is fixed at the moment the server execs. `niri-session` runs
`dbus-update-activation-environment --systemd --all` and only then starts
niri, which is `Before=graphical-session.target` — but niri's own variables
arrive in further stages around the target (measured 2026-10-31 15:16:58: the
unit started with `WAYLAND_DISPLAY` already imported, `NIRI_SOCKET` and
`DISPLAY` still missing). The ExecStart script therefore polls for
`WAYLAND_DISPLAY` and `NIRI_SOCKET` together before exec'ing, so the server
reliably sees those two plus `XDG_SESSION_TYPE` and `XDG_CURRENT_DESKTOP`.
`DISPLAY` (`:0`, Xwayland, spawned on demand) is deliberately not awaited — a
poll for it could wait forever on a session that never spawns an X client.

Start it any earlier — `default.target`, i.e. at boot — and its environment is
frozen *before* that import. Panes then carry no `WAYLAND_DISPLAY`, and every
clipboard tool in them fails: lazygit answers `y` with "No clipboard utilities
available" (its `atotto/clipboard` only consults `wl-copy` when that variable
is set), nvim's `"+` register is empty, and omp's clipboard path is skipped
outright (it gates on `process.env.WAYLAND_DISPLAY`).

The subtlety that made this look intermittent: herdr **restores panes and
resumes their agents at server start** (`session.resume_agents_on_restore`,
default on). A boot-time server therefore execs `omp --resume=…` seconds before
the session exists, and that agent keeps the hole for its whole life — no
in-process repair is possible either, because `Bun.spawn` uses the environment
captured at exec, not a mutated `process.env`. Repairing after the fact cannot
work: the environment has to be right *at spawn*. Two shell-level repairs and an
omp wrapper were tried here before and each only moved the race; the ordering
above removes it.

An ssh-only, pre-login path deliberately does not exist any more: after a reboot
nothing runs herdr until someone logs in at the console. That is acceptable
because the things agents need — the keyring-unlocked `gh` token, the Wayland
socket — only exist after a graphical login anyway. `linger` (geekom's host file)
is still on, so a user manager survives a logout for SSH; it does not start
herdr.

The VM is the exception: its cage kiosk (`hosts/vm/default.nix`) is a **system**
unit and starts no `graphical-session.target`, so the module keeps
`default.target` for a host where `local.desktop.enable` is off. There is no
session import to race there, and panes inherit cage's own environment.

## Update checklist (per nfb bump)

**`nfb`** (`scripts/nfb.sh`, alias in [shell.nix](../modules/home/shell.nix)) does
the mechanical half: it checks each pinned tool's latest release (herdr and the
reviewr plugin alike), asks before writing, then updates the version + both
hashes in [tool-pins.json](../modules/home/tool-pins.json) and re-fetches the
vendored assets whose bytes moved — herdr's two agent assets and reviewr's
plugin manifest, all guarded against upstream path/format changes. So pin,
binaries and assets cannot drift apart. Hashes come from the release's own
SHA256 digest, cross-checked against a
download of this host's asset. herdr has **no flake input**: as a prebuilt FOD the
input fed nothing but an unexercised fallback, so it and its lock nodes are gone —
the `tool-pins.json` entry is the pin of record.

1. `nfb`, answer `y` for herdr (and for reviewr when it offers).
2. `git diff` — `tool-pins.json` (three fields per bumped tool) plus vendored
   assets **if** their bytes moved; `nfb` prints the old → new marker line for
   each re-vendored asset.
   Upstream vendoring renames
   `src/integration/assets/omp/herdr-agent-state.ts` to the `config/omp/…` name;
   the copy is byte-for-byte — review it, never edit it.
3. Re-run the skill install (`npx skills add herdrdev/herdr --skill herdr -g`) —
   still manual, and also needed on a new machine (`nfb` prints the reminder).
4. `git add` everything, `./scripts/check-hosts.sh`: expect `vm` + `geekom`
   drvPaths to move, `hplaptop` byte-identical. `nfb` re-records
   `scripts/drvpath-baseline` itself, so the gate passes without a manual
   `--update-baseline`.
5. `nrp`, rebuild, then `herdr --version` and `herdr integration status` (expect
   `omp: current`) to confirm binary and asset moved together.
6. PR → CI → squash merge per [workflow.md](workflow.md).

**No compile happens** — CI substitutes the ~25 MB static binary (a FOD failure
here means the hash or URL is wrong, not a build issue). The binary is
**static-PIE** (zero NEEDED libraries): no nix-ld dependency and nothing to
ELF-patch — the derivation sets `dontStrip`/`dontPatchELF` and installs the bytes
as-is; never ELF-patch it. The rust/zig toolchain left the closure with the source
build, so a tag bump re-hashes instead of recompiling and `nfu` no longer rebuilds
herdr's binary.

Fallback to the from-source build means re-adding the `herdr` flake input and
`home.packages = [ herdr ];` (see herdr.nix). Cost accepted and named: the trust
boundary widens from "herdr's build recipe" to "upstream's release CI"
(hash-pinned, nobody re-derives).

## Operational gotchas

- Restarting the unit (`systemctl --user restart herdr.service`) kills every
  pane's processes: the default `KillMode` takes the whole cgroup. The layout
  comes back from `session.json`; the agents do not.
- State lives under `~/.config/herdr/` (config, sockets, `session.json`).
  `XDG_CONFIG_HOME` relocates all of it; `HERDR_HOME`/`HERDR_CONFIG_DIR` do
  **not** work, `HERDR_CONFIG_PATH` (single file) does.
- Reclaiming a broken setup: `rm -r ~/.config/herdr` removes sockets, logs and
  session state; the config itself is a store symlink and returns on the next
  activation.
- Tab order is `alt+shift+left`/`alt+shift+right`; there is no "move tab to
  workspace" keybinding — paths are the sidebar (mouse drag) or the socket API
  (`tab.move`).

## See also

- [doc/adopting-tools.md](adopting-tools.md) — the ladder this followed
- [doc/workflow.md](workflow.md) — rebuild aliases, escape-hatch policy, release cycle
- [config/zellij/config.kdl](../config/zellij/config.kdl) — the zellij keymap herdr's alt-singles mirror
- [modules/home/herdr.nix](../modules/home/herdr.nix) — the module (owning comments for both vendored assets)
- upstream docs: herdr.dev/docs
