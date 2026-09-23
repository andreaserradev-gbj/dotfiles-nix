# herdr — terminal workspace manager for coding agents

herdr ([github:herdrdev/herdr](https://github.com/herdrdev/herdr), v0.9.1) is a
terminal workspace manager built around AI coding agents: panes and tabs like
zellij, plus an agent registry that tracks which agent (opencode, claude,
codex, …) runs in which pane. It was trialed on 2026-09-13/14 (Phase 0 of the
[adoption ladder](adopting-tools.md)) and promoted into the flake as a
dev-gated home-layer tool.

**Status: adopted, coexisting with zellij.** Both are installed on dev hosts
(`vm`, `geekom`); zellij's retirement is a separate later PR — see
[Coexistence](#coexistence) below.

## Why this shape

- **Upstream flake, tag-pinned.** herdr is not in nixpkgs, so the package comes
  from its upstream flake — the "upstream flake" row of
  [doc/adopting-tools.md](adopting-tools.md) triage. The input is pinned to
  `?ref=v0.9.1`: an unpinned `github:` input would move on every `nfu`, the
  same wrong pace as tracking a moving branch for a system component.
  The pin is bumped by `nfb` (checklist at the bottom): it writes the version +
  both hashes in [modules/home/tool-pins.json](../modules/home/tool-pins.json),
  this `?ref=` in [flake.nix](../flake.nix), and re-fetches the two vendored
  agent assets from the new tag, all in one run. The `?ref=` must stay a
  literal Nix string — Nix's flake parser rejects a computed input URL
  (verified 2026-09-23), so the pin file cannot feed `inputs.*.url`.
- **`herdr.inputs.nixpkgs.follows = "nixpkgs-unstable"`.** A tool flake carries
  its own nixpkgs into `flake.lock` (the "second nixpkgs" cost documented in
  [adopting-tools.md](adopting-tools.md)). Following our unstable tree — the
  same tree the [workflow escape hatch](workflow.md) already tracks — drops
  that cost; herdr's dependency matrix (zig, rust) resolves fine against it
  (`zig_0_15` at adoption, `zig_0_16` since v0.9.1 — both verified present).
  The escape-hatch comment in
  flake.nix names the consumers: ollama and opencode (via the per-host
  `unstablePkgs` bindings), herdr and omp (each via its own input's follows).
- **Dev-gated home layer.** [modules/home/herdr.nix](../modules/home/herdr.nix)
  wraps its whole body in `lib.mkIf osConfig.local.dev.enable`, exactly like
  [modules/home/zellij.nix](../modules/home/zellij.nix). `hplaptop` (dev off)
  evaluates the module to the empty config: verified at promotion time by her
  drvPath staying byte-identical across Phases 1–2 while `vm` and `geekom`
  moved. The gate is the point, per
  [adopting-tools.md](adopting-tools.md#3-promote--through-the-seam).
- **Threading, not host-gating.** The package reaches HM modules via
  `home-manager.extraSpecialArgs` in flake.nix (the
  [adopting-tools.md](adopting-tools.md) step 2 shape). Phase 1 proved the
  binding is lazy: all three hosts' drvPaths were byte-identical before and
  after threading. The host-gating fallback (`optionalAttrs`, the
  `unstablePkgs` pattern in flake.nix) was prepared but never needed.
- **The binary is upstream's prebuilt release, not a source build**
  ([herdr-prebuilt.nix](../modules/home/herdr-prebuilt.nix), wired via
  `home.packages` in [herdr.nix](../modules/home/herdr.nix)). The from-source
  build measured **4m57s of buildPhase on a fast CI runner** (~6 min with the
  rust-toolchain unpack and zig cache), and it recompiled on EVERY CI run
  because runner stores do not persist — the drv was byte-identical between
  the PR #25 and #26 builds, yet CI rebuilt it both times. The prebuilt
  derivation is a fixed-output fetch of the release binary, SHA256-pinned,
  Apache-2.0, verified **byte-identical** in the store, live
  (`herdr --version`, `herdr config check`).
  - The binary is **static-PIE** (zero NEEDED libraries): no nix-ld
    dependency, nothing to ELF-patch — the derivation sets
    `dontStrip`/`dontPatchELF` and installs the bytes as-is. Simpler than
    the [omp-prebuilt](omp.md) case (no loader override, no Bun-trailer
    trap), but the same rule holds: never ELF-patch it.
  - Tradeoff, accepted and named: the trust boundary widens from "herdr's
    build recipe" to "upstream's release CI" (hash-pinned, nobody
    re-derives). Fallback to the from-source build is one line:
    `home.packages = [ herdr ];` (the flake input's own build).
  - Consequence: herdr and its rust/zig toolchain (rustc, rust-docs, cargo,
    zig, the zig-cache, cargo-vendor — ~1,150 drv paths on geekom) leave the
    closure entirely; a herdr tag bump re-hashes instead of recompiling;
    `nfu` moves of `nixpkgs-unstable` no longer rebuild herdr's binary. The
    flake input stays in the lock: it is the version pin of record and feeds
    the module's package fallback.

## Ownership: Nix-managed vs npx-managed

| artifact | owned by | how it gets there |
|---|---|---|
| herdr binary | Nix | upstream prebuilt FOD ([herdr-prebuilt.nix](../modules/home/herdr-prebuilt.nix)) → `home.packages`, dev-gated; from-source fallback = the `herdr` flake input's package |
| `~/.config/herdr/config.toml` | Nix | `xdg.configFile` from the verbatim asset [config/herdr/config.toml](../config/herdr/config.toml) |
| `~/.config/opencode/plugins/herdr-agent-state.js` | Nix | `xdg.configFile` from the vendored byte-for-byte copy [config/opencode/plugins/herdr-agent-state.js](../config/opencode/plugins/herdr-agent-state.js) |
| `~/.omp/agent/extensions/herdr-omp-agent-state.ts` | Nix | `home.file` from the vendored byte-for-byte copy [config/omp/herdr-omp-agent-state.ts](../config/omp/herdr-omp-agent-state.ts) (added 2026-09-21 with the [omp adoption](omp.md)) |
| agent skill (`~/.agents/skills/herdr/SKILL.md`) | **npx, manual** | `npx skills add herdrdev/herdr --skill herdr -g` |

The plugin lives in `config/opencode/plugins/` and the omp extension in
`config/omp/`, but both are deployed by [modules/home/herdr.nix](../modules/home/herdr.nix),
**not** by opencode.nix / omp.nix — keeping the herdr↔agent couplings in one
greppable place, and each asset's version rides the same flake input as the
binary, so they can never drift apart.

Why the assets are vendored at all: opencode loads plugins from
`~/.config/opencode/plugins/` and omp loads extensions from
`~/.omp/agent/extensions/`; store symlinks pin them to reviewed,
version-matched copies and make a stray install (e.g. `herdr integration
install omp` offering to write its own copy) fail loudly instead of silently
drifting. The omp deployment path uses `home.file` rather than
`xdg.configFile` because omp's base directory is `~/.omp/agent/` (not
`~/.config/omp/`).

The two vendored agent assets carry **independent** version counters — at
herdr v0.9.1 the opencode plugin is 12 and the omp extension is 10. Never
compare one against the other; each is diffed only against the same-file
asset at the new tag (step 3 below).

The agent skill is deliberately **not** vendored: it is npx-managed like the
other skills in `~/.agents/skills`, so it stays editable/fresh without a
rebuild, and is re-run manually per tag bump (below).

## Update checklist (per herdr tag bump)

One command does the mechanical half: **`nfb`** (`scripts/nfb.sh`, alias in
[shell.nix](../modules/home/shell.nix)). It checks upstream's latest release,
asks before writing, then updates the version + both hashes in
[tool-pins.json](../modules/home/tool-pins.json), the `?ref=` in
[flake.nix](../flake.nix), the `herdr` lock entry, and both vendored agent
assets — so pin, binary and assets cannot drift apart. Hashes come from the
release's own SHA256 digest, cross-checked against a download of this host's
asset; the asset files are re-fetched from the new tag and written only if
their bytes changed.

1. `nfb`, answer `y` for herdr.
2. `git diff` — [tool-pins.json](../modules/home/tool-pins.json) (three
   fields), flake.nix, flake.lock, plus the agent assets **if** their bytes
   moved. Each asset carries its own `HERDR_INTEGRATION_VERSION` counter
   (v0.9.1: opencode plugin = 12, omp extension = 10; never compare one
   against the other) — `nfb` prints the old → new marker next to the file, and
   `src/integration/assets/omp/herdr-agent-state.ts` upstream vendors here as
   `config/omp/herdr-omp-agent-state.ts` (renamed on vendoring). The two are
   byte-for-byte copies: review them, never edit them.
3. Re-run the skill install: `npx skills add herdrdev/herdr --skill herdr -g`
   (still manual — `nfb` prints this reminder; also needed on first install of
   a new machine).
4. **No compile happens** — CI substitutes the ~25 MB static binary (a FOD
   failure here means the hash or URL is wrong, not a build issue). The
   rust/zig toolchain is gone from the closure, so the ~5-min herdr
   buildPhase class is gone too.
5. `git add` everything, `./scripts/check-hosts.sh`: expect `vm` + `geekom`
   drvPaths to move, `hplaptop` byte-identical.
6. `nrp`, rebuild, then `herdr --version` and `herdr integration status`
   (expect `omp: current`) to confirm binary and assets moved together.
7. Version literals in this doc's prose (`v0.9.1`, the two markers above) stay
   a manual tail: update them in the same commit if they moved.
8. PR → CI → squash merge per [workflow.md](workflow.md).

Post-rebuild verification for the omp extension:
`herdr integration status` should report `omp: current`.

Note on `zig_0_15`: herdr's build uses zig; it was present in both our
nixpkgs-26.05 pin and nixpkgs-unstable at adoption time. Upstream moved its
flake to `zig_0_16` at v0.9.1 (verified present in our pinned unstable rev
`efe6f071ede9`, and 0.15.2/0.16.0 both remain available in that tree). If a
release bump or tag bump ever fails with a missing zig, check that first.

## The config: what each knob means

The asset [config/herdr/config.toml](../config/herdr/config.toml) is copied
verbatim into place by the module (assets are verbatim, per the repo
convention — edit the asset, not a generator; there is none).

- `onboarding = false` — top-level boolean (not a table).
- `[theme] name = "catppuccin"` — canonical name (`catppuccin-mocha` is an
  alias).
- `[update] version_check = false` — **the only phone-home knob**;
  strace-verified during the trial: with this false, zero AF_INET connects.
  herdr *does* ship a self-updater (`herdr update`, channel set) but it is
  inert under Nix — the store binary cannot self-replace. There is no
  "disable self-updater" config knob to set; `version_check = false` is the
  complete phone-home story. This mirrors opencode's disabled auto-updater
  ([modules/home/opencode.nix](../modules/home/opencode.nix)).

## Keymap: zellij mirroring

Every binding is array-form with BOTH the herdr prefix chord and a bare
single, mirroring zellij's navigation
([config/zellij/config.kdl](../config/zellij/config.kdl)). The prefix chords
keep zellij's alt-direct letters; the bare singles use **alt+arrows**,
mirroring zellij's `Alt left/down/up/right` focus binds
(config/zellij/config.kdl:117-120).

| action | zellij | herdr |
|---|---|---|
| focus pane left/down/up/right | `Alt left/down/up/right` | `prefix+alt+h/j/k/l` and `alt+left/down/up/right` |
| split vertical | `Alt n` | `alt+n` |
| split horizontal | `d` in pane mode | `alt+d` |
| zoom (fullscreen) | `Alt f` | `alt+f` |
| new tab | — (mode-based) | `alt+t` |
| next tab | `Alt o` | `alt+shift+right` |
| previous tab | `Alt i` | `alt+shift+left` |

**Why the bare singles are arrows, not alt+hjkl:** neovim claims `alt+h`
(toggle-hidden in grep/fzf pickers), and any bare alt-letter here swallows it
before it reaches the pane. Arrows leave hjkl to the app inside the pane;
zellij already trains the Alt-arrow habit. Verified against herdr 0.9.0 docs
(same key schema at 0.9.1):
arrow key names are valid key strings, and the ctrl+alt family is the
upstream-recommended conflict-free alternative (we keep alt, which the
terminal transmits fine on Linux).

Provenance notes, kept from the zellij config's own documented asymmetry:

- Tab-move keys: originally `Alt i` / `Alt o` (kept from zellij's
  `MoveTab "left/right"` bindings; `Alt i` has a documented capability gap in
  zellij locked mode that never mattered in practice). Moved to
  `alt+shift+left/right` (2026-09-16) because neovim claims `alt+i`, and
  zellij already passes `alt+i` through to apps in locked mode — a bare
  alt-letter here repeats that conflict class. Shift+arrows keep the
  arrows-for-navigation family (arrows = panes, shift+arrows = tabs) and
   match the browser/VS Code convention. herdr 0.9.0 docs (same key schema at
   0.9.1) use the
   `alt+shift+arrow` shape for resize binds, so the key string parses.
- `Alt n` as split-vertical was kept from zellij's `Alt n → NewPane`.
- `Alt d` as split-horizontal mirrors zellij's pane-mode `d` (`NewPane
  "down"` — a stacked split). herdr's upstream default is `prefix+minus`;
  we keep both the prefix chord default shape and the bare alt single.
- There is **no quit key** in herdr: `prefix+q` *detaches* (server keeps
  running, re-attach with `hd`); killing the server is a CLI action. This is
  a documented upstream gap, not a config choice.
- Pane-focus-left is reached via the chord `prefix+alt+h` (kept from herdr's
  default shape) or the bare `alt+left` single — the same capability as
  zellij's `Alt left`. The bare `alt+h` single was dropped in favour of the
  arrow (see the table above).

**During the trial only the bindings listed in the asset were hand-verified**
(focus chords, `alt+n`, `alt+d`, `alt+f`, `alt+t` — `alt+d` added post-trial
at user request, validated with
`herdr config check` before its first live use). The **alt+arrow focus
singles and alt+shift+arrow tab nav postdate the trial** (2026-09-16,
swapping the bare alt+hjkl and alt+i/o singles out to free them for neovim)
and still need a live `herdr config check` +
keystroke test after the next rebuild. Wider
zellij-mirror bindings (`prefix+g/b/r/[` chords,
`switch_tab = "prefix+1..9"`) were deliberately left OUT of the asset until
each is verified live — extend the asset after testing, don't ship unverified
keymap claims.

## Operational notes

- **Don't nest herdr inside zellij during the trial/coexistence window** —
  both claim `alt+hjkl` and the inner manager's keys win in ways that are
  hard to reason about. Run them in separate terminals.
- State lives under `~/.config/herdr/` (config + sockets + session.json).
  `XDG_CONFIG_HOME` relocates all of it; `HERDR_HOME`/`HERDR_CONFIG_DIR` do
  **not** work; `HERDR_CONFIG_PATH` (single file) does. Relevant only if you
  ever need to move state off the default path.
- Reorder tabs with `alt+shift+left`/`alt+shift+right`; there is no "move
  tab to workspace"
  keybinding — paths are the sidebar (mouse drag) or the socket API
  (`tab.move`).
- Reclaiming a broken setup: `rm -r ~/.config/herdr` removes sockets, logs
  and session state; the config itself is a store symlink and comes back on
  the next activation.

## Coexistence

The adoption keeps **one module per role**: zellij's role (multiplexer) and
herdr's role (agent workspace) overlap enough to coexist but not to merge —
herdr's agent registry is the differentiator; plain pane management is
unchanged muscle memory. The trial ran both side by side (deliberately not
nested) with no keybinding conflict once herdr's keymap mirrored the zellij
alt-singles above. If zellij eventually retires, that is its own PR after a
trial period, per [adopting-tools.md](adopting-tools.md) "Check for overlap".

## Trial record (Phase 0, 2026-09-13/14)

- `nix flake show github:herdrdev/herdr` at v0.9.0 (trial; v0.9.1 re-verified
  at the tag bump): packages for
  x86_64-linux and aarch64-linux; **no homeManagerModules** (hence the
  hand-written module); deps: zig 0.15/0.16 + rust, via oxalica rust-overlay.
- geekom x86_64 run verified (HEAD and pinned tag; rev b99002a).
- VM runtime check skipped — the VM is no longer installed on the Mac; the
  flake still evaluates the `nixos` host harmlessly.
- `herdr config check` passed on the scratch config (with a negative control:
  a deliberately broken file fails loudly).
- Keymap live-verified: alt+`hjkl` focus, `alt+n` split, `alt+f` zoom,
  `alt+t`/`alt+o`/`alt+i` tabs; catppuccin renders; no onboarding screen.
- strace: zero network connects with `version_check = false`.
- Plugin asset confirmed self-contained at the tag
  (`HERDR_INTEGRATION_VERSION=11`; only `node:net`; sibling files at tag are
  tests only — vendoring exactly one file is correct).

## See also

- [doc/adopting-tools.md](adopting-tools.md) — the ladder this followed
- [doc/workflow.md](workflow.md) — rebuild aliases, escape-hatch policy,
  release cycle
- [config/zellij/config.kdl](../config/zellij/config.kdl) — the zellij keymap
  herdr's alt-singles mirror
- [modules/home/herdr.nix](../modules/home/herdr.nix) — the module (owning
  comments for both vendored agent assets + the skill)
- upstream docs: herdr.dev/docs