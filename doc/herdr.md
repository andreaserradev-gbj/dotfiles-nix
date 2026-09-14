# herdr — terminal workspace manager for coding agents

herdr ([github:herdrdev/herdr](https://github.com/herdrdev/herdr), v0.9.0) is a
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
  `?ref=v0.9.0`: an unpinned `github:` input would move on every `nfu`, the
  same wrong pace as tracking a moving branch for a system component.
  Bumping = edit `?ref=` in [flake.nix](../flake.nix), `nix flake lock`,
  commit both.
- **`herdr.inputs.nixpkgs.follows = "nixpkgs-unstable"`.** A tool flake carries
  its own nixpkgs into `flake.lock` (the "second nixpkgs" cost documented in
  [adopting-tools.md](adopting-tools.md)). Following our unstable tree — the
  same tree the [workflow escape hatch](workflow.md) already tracks — drops
  that cost; herdr's dependency matrix (zig, rust) resolves fine against it
  (`zig_0_15` verified present in both pins). The escape-hatch comment in
  flake.nix names the two consumers: ollama (geekom, via `unstablePkgs`) and
  herdr (via its input's follows).
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

## Ownership: Nix-managed vs npx-managed

| artifact | owned by | how it gets there |
|---|---|---|
| herdr binary | Nix | `herdr.packages.${pkgs.system}.default` → `home.packages`, dev-gated |
| `~/.config/herdr/config.toml` | Nix | `xdg.configFile` from the verbatim asset [config/herdr/config.toml](../config/herdr/config.toml) |
| `~/.config/opencode/plugins/herdr-agent-state.js` | Nix | `xdg.configFile` from the vendored byte-for-byte copy [config/opencode/plugins/herdr-agent-state.js](../config/opencode/plugins/herdr-agent-state.js) |
| agent skill (`~/.agents/skills/herdr/SKILL.md`) | **npx, manual** | `npx skills add herdrdev/herdr --skill herdr -g` |

The plugin lives in `config/opencode/plugins/` but is deployed by
`modules/home/herdr.nix`, **not** `opencode.nix` — keeping the
herdr↔opencode coupling in one greppable place, and the plugin version rides
the same flake input as the binary, so they can never drift apart.

Why the plugin is vendored at all: opencode loads plugins from
`~/.config/opencode/plugins/`; a store symlink pins it to a reviewed,
version-matched copy and makes a stray install (e.g. herdr offering to
upgrade it) fail loudly instead of silently drifting.

The agent skill is deliberately **not** vendored: it is npx-managed like the
other skills in `~/.agents/skills`, so it stays editable/fresh without a
rebuild, and is re-run manually per tag bump (below).

## Update checklist (per herdr tag bump)

1. Edit `?ref=vX.Y.Z` on the herdr input in [flake.nix](../flake.nix).
2. `nix flake lock` and `git add flake.lock`.
3. **Re-check the vendored plugin against the new tag:**
   compare `HERDR_INTEGRATION_VERSION` in
   `src/integration/assets/opencode/herdr-agent-state.js` at the new tag with
   the vendored copy's marker (v0.9.0 = 11). If changed, re-vendor
   byte-for-byte (`cp` from the tag-resolved `nix flake metadata …` source
   path) — the plugin and binary must stay version-matched.
4. Re-run the skill install: `npx skills add herdrdev/herdr --skill herdr -g`
   (also needed on first install of a new machine).
5. `git add` everything, `./scripts/check-hosts.sh`: expect `vm` + `geekom`
   drvPaths to move, `hplaptop` byte-identical.
6. PR → CI → squash merge per [workflow.md](workflow.md).

Note on `zig_0_15`: herdr's build uses zig; it was present in both our
nixpkgs-26.05 pin and nixpkgs-unstable at adoption time. If a release bump or
tag bump ever fails with a missing zig, check that first.

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

Every binding is array-form with BOTH the herdr prefix chord and the bare alt
single, mirroring zellij's alt-direct navigation
([config/zellij/config.kdl](../config/zellij/config.kdl)):

| action | zellij | herdr |
|---|---|---|
| focus pane h/j/k/l | `Alt h/j/k/l` | `prefix+alt+h…` and `alt+h…` |
| split vertical | `Alt n` | `alt+n` |
| split horizontal | `d` in pane mode | `alt+d` |
| zoom (fullscreen) | `Alt f` | `alt+f` |
| new tab | — (mode-based) | `alt+t` |
| next tab | `Alt o` | `alt+o` |
| previous tab | `Alt i` | `alt+i` |

Provenance notes, kept from the zellij config's own documented asymmetry:

- `Alt i` / `Alt o` as tab-move keys were kept from zellij's
  `MoveTab "left/right"` bindings; `Alt i` has a documented capability gap in
  zellij locked mode that never mattered in practice. herdr has no such mode
  distinction, so both work uniformly.
- `Alt n` as split-vertical was kept from zellij's `Alt n → NewPane`.
- `Alt d` as split-horizontal mirrors zellij's pane-mode `d` (`NewPane
  "down"` — a stacked split). herdr's upstream default is `prefix+minus`;
  we keep both the prefix chord default shape and the bare alt single.
- There is **no quit key** in herdr: `prefix+q` *detaches* (server keeps
  running, re-attach with `hd`); killing the server is a CLI action. This is
  a documented upstream gap, not a config choice.
- `Alt h` reaches pane-focus-left via the chord `prefix+alt+h` in herdr's
  default, plus the bare `alt+h` single we bound — the same capability as
  zellij's `Alt h`/`Alt left`.

**During the trial only the bindings listed in the asset were hand-verified**
(focus chords + singles, `alt+n`, `alt+d`, `alt+f`, `alt+t`, `alt+o`,
`alt+i` — `alt+d` added post-trial at user request, validated with
`herdr config check` before its first live use). Wider
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
- Reorder tabs with `alt+o`/`alt+i`; there is no "move tab to workspace"
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

- `nix flake show github:herdrdev/herdr` at v0.9.0: packages for
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
  comments for plugin + skill)
- upstream docs: herdr.dev/docs