# herdr — terminal workspace manager for coding agents

herdr ([github:herdrdev/herdr](https://github.com/herdrdev/herdr)) is a
terminal workspace manager built around AI coding agents: panes and tabs like
zellij, plus an agent registry that tracks which agent (opencode, claude, codex,
…) runs in which pane. It was promoted into the flake as a dev-gated home-layer
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
`lib.mkIf osConfig.local.dev.enable`, like zellij and opencode; `hplaptop` (dev
off) evaluates it to the empty config.

| artifact | owned by | how it gets there |
|---|---|---|
| herdr binary | Nix | upstream's prebuilt release FOD ([herdr-prebuilt.nix](../modules/home/herdr-prebuilt.nix), called with `callPackage` — no host carries a `herdr` arg) → `home.packages`, dev-gated; version + both hashes from the `herdr` entry in [tool-pins.json](../modules/home/tool-pins.json) |
| `~/.config/herdr/config.toml` | Nix | `xdg.configFile` from the verbatim asset [config/herdr/config.toml](../config/herdr/config.toml) |
| `~/.config/opencode/plugins/herdr-agent-state.js` | Nix | `xdg.configFile` from the vendored byte-for-byte copy [config/opencode/plugins/herdr-agent-state.js](../config/opencode/plugins/herdr-agent-state.js) |
| `~/.omp/agent/extensions/herdr-omp-agent-state.ts` | Nix | `home.file` from the vendored byte-for-byte copy [config/omp/herdr-omp-agent-state.ts](../config/omp/herdr-omp-agent-state.ts) — omp's base directory is `~/.omp/agent/`, not `~/.config/omp/` |
| agent skill (`~/.agents/skills/herdr/SKILL.md`) | **npx, manual** | `npx skills add herdrdev/herdr --skill herdr -g` |

Both agent assets are deployed by [modules/home/herdr.nix](../modules/home/herdr.nix),
**not** by opencode.nix / omp.nix: the herdr↔agent couplings stay in one
greppable place, and the single `nfb` run re-fetches them from the same release
tag as the binary, so they cannot drift apart. Vendoring pins them to reviewed,
version-matched copies and makes a stray install (`herdr integration install omp`
offering to write its own copy) fail loudly instead of drifting silently. The two
carry **independent** version counters (the `HERDR_INTEGRATION_VERSION` marker at
the top of each file). Never compare one against the other; each is diffed only
against the same-file asset at the new tag. The skill is deliberately *not*
vendored: npx-managed like the other skills, it stays editable/fresh without a
rebuild and is re-run manually per bump.

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
  for Nix installs", and there is no "disable self-updater" setting to make. Same
  decision as opencode's disabled auto-updater
  ([modules/home/opencode.nix](../modules/home/opencode.nix)).

**Keymap.** Every binding is array-form; each focus binding carries BOTH a herdr
prefix chord and a bare single, and the rest one key each — the whole set mirrors
zellij's navigation
([config/zellij/config.kdl](../config/zellij/config.kdl); the asset is the source
of truth for the list). The bare singles are **arrows**, not `alt+hjkl`: neovim
claims `alt+h` (toggle-hidden in grep/fzf pickers), and any bare alt-letter here
swallows it before it reaches the pane. Arrows leave hjkl to the app inside the
pane, and zellij already trains the Alt-arrow habit. Two upstream gaps worth
knowing: there is **no quit key** (`prefix+q` *detaches* — the server keeps
running; killing it is a CLI action), and wider zellij-mirror bindings were
deliberately left out of the asset — extend it after testing, don't ship
unverified keymap claims. `herdr config check` validates the asset (it prints
`config: ok`).

## Update checklist (per herdr tag bump)

**`nfb`** (`scripts/nfb.sh`, alias in [shell.nix](../modules/home/shell.nix)) does
the mechanical half: it checks upstream's latest release, asks before writing,
then updates the version + both hashes in
[tool-pins.json](../modules/home/tool-pins.json) and re-fetches both vendored
agent assets if their bytes changed — so pin, binary and assets cannot drift
apart. Hashes come from the release's own SHA256 digest, cross-checked against a
download of this host's asset. herdr has **no flake input**: as a prebuilt FOD the
input fed nothing but an unexercised fallback, so it and its lock nodes are gone —
the `tool-pins.json` entry is the pin of record.

1. `nfb`, answer `y` for herdr.
2. `git diff` — `tool-pins.json` (three fields) plus the agent assets **if** their
   bytes moved; `nfb` prints the old → new `HERDR_INTEGRATION_VERSION` marker next
   to each. Upstream vendoring renames
   `src/integration/assets/omp/herdr-agent-state.ts` to the `config/omp/…` name;
   the copies are byte-for-byte — review them, never edit them.
3. Re-run the skill install (`npx skills add herdrdev/herdr --skill herdr -g`) —
   still manual, and also needed on a new machine (`nfb` prints the reminder).
4. `git add` everything, `./scripts/check-hosts.sh`: expect `vm` + `geekom`
   drvPaths to move, `hplaptop` byte-identical.
5. `nrp`, rebuild, then `herdr --version` and `herdr integration status` (expect
   `omp: current`) to confirm binary and assets moved together. The same output
   also shows `opencode: needs repair`: opencode's integration is multi-file (the
   plugin plus a `herdr-tui-session.js` and a `tui.jsonc` entry, and only the
   plugin is vendored), so that flag is the unvendored companions, not a version
   mismatch.
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
