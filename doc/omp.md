# omp (oh-my-pi) — the second coding agent

omp ([github:can1357/oh-my-pi](https://github.com/can1357/oh-my-pi), v18.2.8)
is a coding agent — a fork of Mario Zechner's Pi with an expanded tool surface
(LSP wired in, DAP debugging, subagents, web search). It was adopted on
2026-09-21 as a **coexisting** second harness alongside
[opencode](../modules/home/opencode.nix), following the
[adoption ladder](adopting-tools.md). Both are installed on dev hosts; which
one is *primary* is deliberately not decided by this document — a benchmark
harness (`~/code/agent-bench`, own PRD) is measuring both on the same models,
and its results, not this doc, will drive any primary-harness switch.

## Why this shape

- **Upstream flake, tag-pinned** (`?ref=v18.2.8` in [flake.nix](../flake.nix)).
  omp is not in nixpkgs (searched 2026-09-21), so the package comes from its
  upstream flake — the "upstream flake" row of the
  [triage ladder](adopting-tools.md). An unpinned `github:` input would move
  on every `nfu`; bumping = edit `?ref=`, `nix flake lock`, commit both.
- **`omp.inputs.nixpkgs.follows = "nixpkgs-unstable"`** — the same
  second-nixpkgs-cost argument as
  [herdr](herdr.md#why-this-shape): a tool flake carries its own nixpkgs
  into `flake.lock` unless its input follows ours. omp's lock is cut against
  nixos-unstable, so the follow is exact.
  Additionally `omp.inputs.nixpkgs-darwin-x64.follows = "nixpkgs"`: that
  input only matters for x86_64-darwin (omp keeps Intel-mac support on the
  last stable darwin tree), no host here is one, and following it raw would
  add a **third** nixpkgs tree to the lock for zero benefit.
- **Lockfile cost, accepted and named**: omp's inputs add `bun2nix`,
  `nix-bun` and `oxalica/rust-overlay` — omp's Rust core (~80k lines of
  natives) and bun runtime are built from source. The nix-community binary
  cache covers the *toolchain* deps but **no cache carries omp itself**
  (verified 2026-09-22 at v18.2.8: `nix path-info --store
  https://nix-community.cachix.org` reports the prebuilt store path "not
  valid" — `nix-community.cachix.org/nar/*.narinfo` 404s for it; omp's own
  `nix.yml` CI evaluates but never builds/publishes).
- **The binary is upstream's prebuilt release, not a source build**
  ([omp-prebuilt.nix](../modules/home/omp-prebuilt.nix), wired via
  `programs.omp.package` in [omp.nix](../modules/home/omp.nix)). The
  from-source build cost was measured on the first PR: **31 min on a fast
  CI runner**; the full build cycle exceeds an hour locally, and it would
  re-trigger on EVERY `nfu` that moves `nixpkgs-unstable` (the omp flake
  input follows that tree) — an unbounded recurring cost. The prebuilt
  derivation is a fixed-output fetch of the release binary (the same one
  upstream's install script and Homebrew ship), SHA256-pinned, MIT, and
  verified **byte-identical** in the store, live against the local daemon.
  - It depends on nix-ld (dev-gated) for its `/lib64` loader — stock NixOS
    without the dev seam would not run it (irrelevant here: the module is
    dev-gated anyway).
  - **It must never be ELF-patched** (`autoPatchelfHook`, `strip`,
    `patchelf`): omp is a Bun standalone executable that locates its
    embedded payload via absolute trailer offsets — patching shifts the
    section table (+144 bytes at v18.2.7) and silently degrades the binary
    into a plain `bun` runtime (`omp --version` → `Bun v1.4.2`). Verified
    experimentally; the derivation sets `dontStrip`/`dontPatchELF` and
    documents this.
  - Tradeoff, accepted and named: the trust boundary widens from "omp's
    build recipe" to "upstream's release CI" (hash-pinned, nobody
    re-derives). Fallback to the from-source build is one line:
    `package = omp.packages.${pkgs.stdenv.hostPlatform.system}.default;`
  - Consequence for CI: **an omp tag bump no longer compiles anything** —
    a bump edits the pin in omp-prebuilt.nix + `?ref=` in flake.nix
    (they must agree), re-hashes, and CI substitutes a ~244 MB binary.
    `nfu` moves of `nixpkgs-unstable` no longer touch omp's binary either
    (the flake input is still locked for the HM module + version pin of
    record). The 31-minute CI compile class is gone entirely.
- **Binary-cache trust is system-level** ([common.nix](../modules/nixos/common.nix)):
  omp's flake advertises nix-community's cache via `nixConfig`, but that is
  only a prompt — an untrusted user's "y" still yields "warning: ignoring
  untrusted substituter" and every dependency builds locally (hit live
  during the trial). `nix.settings.substituters`/`trusted-public-keys` in
  commonModules make the substitution unconditional. This is machine-level
  config, so it moves **all three** drvPaths including hplaptop — a
  config-only move (no package diffs).
- **Dev-gated home layer.** [modules/home/omp.nix](../modules/home/omp.nix)
  wraps its whole body in `lib.mkIf osConfig.local.dev.enable`, exactly like
  [herdr.nix](herdr.md) and [opencode.nix](../modules/home/opencode.nix).
  hplaptop (dev off) evaluates it to the empty config. The flake input is
  threaded via `home-manager.extraSpecialArgs` (the
  [herdr](herdr.md#why-this-shape) shape); the **input**, not the package —
  omp's own `homeManagerModules.default` defaults `programs.omp.package` to
  its flake's own build.

## The one-module-per-role question

[adopting-tools.md](adopting-tools.md) flags "a second coding agent" as an
overlap to justify. The resolution: **both stay, coexisting**, because they
are being *measured* against each other (agent-bench harness, same tasks ×
same models) and because the roles differ in practice today — opencode as the
known-good daily driver, omp as the challenger with the wired-in IDE surface
(LSP/DAP, subagents). omp's opencode-compat provider is deliberately left
OFF (no `enabledProviders`): enabling it would also load opencode's herdr
plugin into omp (written against opencode's plugin API — unverified there)
and feed opencode-only settings keys into omp's strict config merge. The
result is duplicated MCP config instead — see the drift warning below.

## Ownership: Nix-managed vs manual/stateful

| artifact | owned by | how it gets there |
|---|---|---|
| omp binary | Nix | `omp` flake input → `programs.omp.enable` (upstream HM module), dev-gated |
| `~/.omp/agent/config.yml` | **Nix-declared, writable copy** | upstream HM module: `programs.omp.settings`; re-imposed on every `home-manager switch` |
| `~/.omp/agent/mcp.json` | Nix | `home.file` in [omp.nix](../modules/home/omp.nix), store symlink |
| herdr extension (`~/.omp/agent/extensions/herdr-omp-agent-state.ts`) | Nix | vendored asset, deployed by [herdr.nix](../modules/home/herdr.nix) — see [herdr.md](herdr.md) |
| zsh completions | Nix | cached generator in omp.nix `initExtra` (regenerates when the omp binary is newer than the cache) |
| **ollama.com API key** | **manual, per host** | first-run wizard or `/login ollama-cloud` → stored in `~/.omp/agent/agent.db` |
| sessions, logs, caches | stateful | `~/.omp/agent/{sessions,logs,cache}` — Nix-ignorable |

The config.yml split deserves spelling out: **omp rewrites its own
config.yml at runtime** (`/settings`, `/model` role persistence, onboarding
completion — flock + atomic rewrite), and the upstream module handles that by
deploying a *writable copy* and re-imposing the declared settings on every
switch. Runtime edits survive until the next switch, then lose to the
declaration. That is why the routing knobs omp would otherwise write at
runtime are **declared** in `programs.omp.settings` instead:

- `modelRoles.default = "ollama/deepseek-v4.1-flash:cloud:high"` — the same
  model opencode's `model` names (one edit per file to switch), plus omp's
  `provider/model:level` thinking-level suffix: `:high` is what the runtime
  pick carried and is declared so the next switch re-imposes it rather than
  dropping to the model's default tier. opencode's schema has no equivalent
  suffix. No `models.yml` at all: omp discovers ollama implicitly (native
  `/api/tags` + `/api/show`), so per-tag
  context windows and capabilities come from the daemon — the
  stale-`limit`-comments maintenance class in
  [opencode.nix](../modules/home/opencode.nix) cannot recur here.
- `modelRoles.web = "web/ollama"` — omp's `web_search` walks dedicated
  search providers, never an LLM; without this it falls to the keyless
  chain (duckduckgo/startpage HTTP scrapes, then browser-backed
  google/ecosia/mojeek that need a Chromium daemon — absent on these hosts).
  `web/ollama` is omp's native provider for
  `ollama.com/api/web_search` — the same backend opencode reaches
  transparently through the signed-in daemon's cloud models. Searches cost
  ollama.com API quota (free tier), not scrape bandwidth.
- `setupVersion = 2` + `"startup.setupWizard" = false` — onboarding
  suppression. The first is what the wizard writes (marking complete); the
  second blanks all onboarding scenes even if a future omp release bumps
  `CURRENT_SETUP_VERSION` — no surprise wizard after a tag bump. Both traced
  in omp's source (main.ts cold-launch gate, selectSetupScenes), not guessed.

### The per-host API key (manual step, like `ollama signin`)

The ollama.com credential is **not** declarable — it is the account's API-key
form (create at ollama.com/settings/keys, free tier), pasted once per dev
host into omp's auth store (`agent.db`, SQLite, app-local). This mirrors the
daemon's own `ollama signin` documented in
[opencode.nix](../modules/home/opencode.nix): the cloud model itself is
reached through the local daemon (keyless from the agent's perspective), but
omp's *search* provider needs the key directly. `agent.db` is outside Nix's
reach and survives rebuilds and GC — only the binary is transient. A fresh
host needs: rebuild (binary + routing) → run `omp` → paste key when asked
(or `/login` → ollama-cloud). The setup wizard is otherwise suppressed.

## MCP: the two-file drift warning

The two MCP servers (nixos, context7) are declared **twice**, in native
shape per agent:

- opencode: `mcp` key in [opencode.json](../modules/home/opencode.nix)
  (`type: local/remote`, `{env:VAR}` interpolation)
- omp: `mcpServers` in `~/.omp/agent/mcp.json` (Claude-style,
  `${VAR}` interpolation, `home.file` store symlink)

**An edit to either server must land in both files.** This duplication is
the accepted cost of keeping omp's opencode-compat provider off (choice and
reasons above); the files cross-reference each other. The context7 auth
chain is identical in both: sops-nix puts the key in `/run/secrets`
(dev hosts only), the guarded `shell.nix` export feeds the environment, and
the empty-var fallback yields context7's anonymous mode instead of a broken
request.

## herdr integration

Like the opencode plugin, the omp extension is vendored byte-for-byte from
herdr's source tree and deployed by
[herdr.nix](../modules/home/herdr.nix) — keeping both herdr↔agent couplings
greppable in one place. The two assets carry **independent** version
counters (v0.9.1: opencode plugin = 12, omp extension = 10); the tag-bump
checklist in [herdr.md](herdr.md) covers both. Verify with
`herdr integration status` (expect `omp: current`).

## Operational notes

- **Where settings live**: `~/.omp/agent/config.yml` (main, HM-owned as a
  writable copy), `<cwd>/.omp/config.yml` (project overrides), `agent.db`
  (auth/sessions/MCP OAuth), `mcp.json`, `models.yml` (absent here), logs
  under `~/.omp/logs`. `omp config path` prints the active agent dir;
  `PI_CODING_AGENT_DIR` relocates it (herdr's omp integration honors the
  same variable).
- **The updater refuses a Nix-managed binary** (source-verified at v18.2.8,
  `packages/coding-agent/src/cli/update-cli.ts`): `resolveUpdateMethod`
  classifies any path under `/nix/store` as `"nix"`, and `omp update` then
  exits with "This installation is managed by Nix and cannot update itself."
  So Nix ownership is safe by upstream guard, **not** by an absent updater —
  the "no self-updater exists" claim that stood here until 2026-09-22 was
  wrong and is corrected at this bump. The phone-home half *is* declarable and
  is switched off: `"startup.checkUpdate" = false` in
  [omp.nix](../modules/home/omp.nix). Its default (`true`) GETs the GitHub
  releases API on every launch — `main.ts` `checkForNewVersion` →
  `getLatestRelease`, 5 s timeout — to announce a version this install cannot
  take. Same decision as herdr's `update.version_check = false` and
  opencode's `autoupdate = false`; the tag pin in flake.nix is the version
  story.
- `nix run github:can1357/oh-my-pi` (the trial invocation) is **ephemeral** —
  no GC root, swept by `ngca`; the installed binary from the module is the
  permanent path.
- The omp `browser` tool (Chromium automation) is currently unwired — its
  browser daemon needs a Chromium executable override
  (`PUPPETEER_EXECUTABLE_PATH`; the bundled Puppeteer download cannot work
  on NixOS). Search does not need it (`modelRoles.web = "web/ollama"`).
  Wiring Brave in is a trial item if omp ever becomes primary.
- **Benchmark**: `~/code/agent-bench` (own repo, own PRD) runs both agents
  headless on identical tasks. Its omp runner should invoke the installed,
  pinned binary now that it exists — not `nix run …main` (unpinned), which
  would let a release change the harness under recorded results.

## Update checklist (per omp tag bump)

1. Edit the version + both hashes in
   [omp-prebuilt.nix](../modules/home/omp-prebuilt.nix) (the glibc asset for
   each arch; re-hash with `nix hash convert --hash-algo sha256 --to sri` or
   let the FOD error print the expected hash).
2. Edit `?ref=vX.Y.Z` on the omp input in [flake.nix](../flake.nix) — must
   agree with step 1 (the HM module + settings are written for that
   version's compiled-in `CURRENT_SETUP_VERSION`).
3. `nix flake lock` and `git add flake.lock`.
4. Re-vendor the herdr omp extension if its version marker changed at the
   new tag (same checklist as [herdr.md](herdr.md) step 3 — the extension
   rides the *herdr* input, so this only coincides with omp bumps).
5. **No compile happens** — CI substitutes the ~244 MB prebuilt (a FOD
   failure here means the hash or URL is wrong, not a build issue).
6. `git add` everything, `./scripts/check-hosts.sh`: expect `vm` + `geekom`
   drvPaths to move, `hplaptop` byte-identical (dev-gated).
7. PR → CI → squash merge per [workflow.md](workflow.md).

## Trial record (Phase 0, 2026-09-21)

- `nix run github:can1357/oh-my-pi` (unpinned main ≈ v18.2.7) on geekom:
  built from source (no cache carries it — substituter warning observed and
  root-caused, fixed in common.nix).
- From-source cost measured at adoption: **31 min on the CI runner** —
  motivating the prebuilt switch (above) the same day.
- Prebuilt verification (2026-09-21): store binary byte-identical to the
  release asset; `omp --version`, live model call via the local daemon, and
  `omp completions zsh` all pass. The autoPatchelfHook variant was built
  first, found silently degraded to `bun`, root-caused (Bun-standalone
  trailer offsets), and fixed by removing all ELF patching.
- First-run wizard observed, including the ollama-cloud sign-in step:
  expected — omp's native search provider needs its own credential (see
  above); key entered, web search verified working by the user.
- Skills: `~/.agents/skills/` (18 skills, npx-managed) load by default —
  omp treats `.agents/skills` as its canonical location; zero config.
- Model discovery: implicit ollama provider resolves
  `ollama/glm-5.3-flash:cloud` with daemon-reported limits.
- Source-traced (not guessed): onboarding gates (main.ts, setup/wizard.ts,
  settings-schema.ts), search provider chain (web/search/index.ts,
  providers/ollama.ts, providers/registry), mcp.json discovery paths,
  auth store location, HM module behavior (writable config.yml copy).

## See also

- [doc/herdr.md](herdr.md) — the herdr adoption (same flake pattern); owns
  the omp extension asset
- [modules/home/opencode.nix](../modules/home/opencode.nix) — the first
  agent; holds the MCP block this module mirrors
- [doc/adopting-tools.md](adopting-tools.md) — the ladder this followed
- [doc/workflow.md](workflow.md) — rebuild aliases, release cycle
- upstream docs: [omp.sh/docs](https://omp.sh/docs)