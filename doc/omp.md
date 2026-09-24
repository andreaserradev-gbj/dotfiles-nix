# omp (oh-my-pi) — the second coding agent

omp ([github:can1357/oh-my-pi](https://github.com/can1357/oh-my-pi)) is a coding
agent — a fork of Mario Zechner's Pi with an expanded tool surface (LSP wired in,
DAP debugging, subagents, web search). It was adopted through the
[adoption ladder](adopting-tools.md) as a **coexisting** second harness alongside
[opencode](../modules/home/opencode.nix), and is dev-gated like herdr.

Which agent is *primary* is deliberately not decided here: a benchmark harness
(`~/code/agent-bench`, own PRD; same tasks × same models) will drive any switch,
and it should invoke the installed, pinned binary — never `nix run …main`, which
would let a release change the harness under recorded results.

## Ownership: Nix-managed vs manual/stateful

[modules/home/omp.nix](../modules/home/omp.nix) wraps its whole body in
`lib.mkIf osConfig.local.dev.enable`; `hplaptop` (dev off) evaluates it to the
empty config. The flake input is threaded via `home-manager.extraSpecialArgs` —
the threading shape [adopting-tools.md](adopting-tools.md) step 2 requires when
the *package* comes from a flake input (herdr, a locally built FOD, needs none).

| artifact | owned by | how it gets there |
|---|---|---|
| omp binary | Nix | `omp` flake input (tag-pinned, `programs.omp.package` → [omp-prebuilt.nix](../modules/home/omp-prebuilt.nix)); version + both hashes from the `omp` entry in [tool-pins.json](../modules/home/tool-pins.json) |
| `~/.omp/agent/config.yml` | **Nix-declared, writable copy** | upstream HM module: `programs.omp.settings`; re-imposed on every `home-manager switch` |
| `~/.omp/agent/mcp.json` | Nix | `home.file` in [omp.nix](../modules/home/omp.nix), store symlink |
| `~/.omp/agent/AGENTS.md` (global agent rules) | Nix | `home.file` in omp.nix, store symlink — the same asset opencode loads as its global rules ([opencode.nix](../modules/home/opencode.nix)) |
| herdr extension (`~/.omp/agent/extensions/herdr-omp-agent-state.ts`) | Nix | vendored asset, deployed by [herdr.nix](../modules/home/herdr.nix) — see [herdr.md](herdr.md) |
| zsh completions | Nix | cached generator in omp.nix (regenerates when the binary is newer than the cache) |
| **ollama.com API key** | **manual, per host** | first-run wizard or `/login ollama-cloud` → `~/.omp/agent/agent.db` |
| sessions, logs, caches | stateful | `~/.omp/agent/{sessions,logs,cache}` — Nix-ignorable |

## What Nix declares

**omp rewrites its own `config.yml` at runtime** (`/settings`, `/model` role
persistence, onboarding completion — flock + atomic rewrite), so the upstream
module deploys a *writable copy* and re-imposes the declared `programs.omp.settings`
on every switch: a runtime edit survives until the next `home-manager switch`,
then loses to the declaration. **Anything not declared in
[omp.nix](../modules/home/omp.nix) is silently lost at the next rebuild** — extend
that block rather than re-picking at runtime. The declared keys and their reasons
are commented there; two consequences worth stating here:

- No `models.yml`: omp discovers ollama implicitly (`/api/tags` + `/api/show`), so
  per-tag context windows and capabilities come from the daemon — the
  stale-`limit` maintenance class in [opencode.nix](../modules/home/opencode.nix)
  cannot recur here.
- Nix ownership is safe by upstream guard, not by an absent updater:
  `resolveUpdateMethod` classifies any `/nix/store` path as `"nix"` and `omp
  update` then exits with "This installation is managed by Nix and cannot update
  itself."

## The per-host API key (manual, like `ollama signin`)

The ollama.com credential is not declarable — it is the account's API-key form
(create at ollama.com/settings/keys, free tier), pasted once per dev host into
omp's auth store (`agent.db`, SQLite, app-local). This mirrors the daemon's own
`ollama signin`: the cloud model is reached through the local daemon (keyless from
the agent's perspective), but omp's *search* provider needs the key directly.
`agent.db` is outside Nix's reach and survives rebuilds and GC. A fresh host needs:
rebuild (binary + routing) → run `omp` → paste the key when asked (or `/login` →
ollama-cloud); the wizard is otherwise suppressed.

## MCP: the two-file drift warning

The two MCP servers (nixos, context7) are declared **twice**, in native shape per
agent: the `mcp` key in [opencode.json](../modules/home/opencode.nix)
(`{env:VAR}` interpolation) and `mcpServers` in `~/.omp/agent/mcp.json`
(Claude-style `${VAR}`, `home.file` store symlink). **An edit to either server must
land in both files** — the accepted cost of keeping omp's opencode-compat provider
off ([omp.nix](../modules/home/omp.nix) carries the reasons). The context7 auth
chain is identical in both: sops-nix puts the key in `/run/secrets` (dev hosts
only — [secrets.md](secrets.md)), the guarded
[shell.nix](../modules/home/shell.nix) export feeds the environment, and the
empty-var fallback yields context7's anonymous mode instead of a broken request.

## herdr integration

Like the opencode plugin, the omp extension is vendored byte-for-byte from herdr's
source tree and deployed by [herdr.nix](../modules/home/herdr.nix) — keeping both
herdr↔agent couplings greppable in one place. The two assets carry **independent**
version counters, and the tag-bump checklist in [herdr.md](herdr.md) covers both.
Verify with `herdr integration status` (expect `omp: current`).

## Update checklist (per omp tag bump)

**`nfb`** (`scripts/nfb.sh`, alias in [shell.nix](../modules/home/shell.nix)) does
the mechanical half: it checks upstream's latest release, asks before writing, then
updates the version + both hashes in
[tool-pins.json](../modules/home/tool-pins.json), the `?ref=` in
[flake.nix](../flake.nix) and the lock entry for the `omp` input — so the pin and
the binary can no longer disagree. Hashes come from the release's own SHA256
digest, cross-checked against a download of this host's asset. The `?ref=` must
stay a literal Nix string (a computed input URL is rejected by the flake parser),
which is why the pin file cannot feed `inputs.*.url` — see the comment on the input.

1. `nfb`, answer `y` for omp. The HM module and its settings are written for the
   pinned version's compiled-in `CURRENT_SETUP_VERSION`, so the pin bump and the
   settings move together.
2. `git diff` — `tool-pins.json` (three fields) + `flake.nix` + `flake.lock`,
   nothing else.
3. `git add` everything, `./scripts/check-hosts.sh`: expect the dev hosts to move,
   `hplaptop` byte-identical (dev-gated).
4. **No compile happens** — CI substitutes the ~244 MB prebuilt, so a FOD failure
   here means the hash or URL is wrong, not a build issue.
5. `nrp`, rebuild, then `omp --version` on the host to confirm the binary moved
   with the pin.
6. PR → CI → squash merge per [workflow.md](workflow.md).

## Gotchas

- **Never ELF-patch the binary** (`autoPatchelfHook`, `strip`, `patchelf`): omp is
  a Bun standalone executable that finds its embedded payload via absolute trailer
  offsets, so patching shifts the section table and silently degrades the binary
  into a plain `bun` runtime (`omp --version` → `Bun v1.4.2`). The derivation sets
  `dontStrip`/`dontPatchELF` and documents this. It depends on nix-ld (dev-gated)
  for its `/lib64` loader — stock NixOS without the dev seam would not run it.
- **The binary is upstream's prebuilt release, not a source build**
  ([omp-prebuilt.nix](../modules/home/omp-prebuilt.nix) says why): no cache carries
  omp, the from-source build measured **31 min on a fast CI runner**, and it would
  re-trigger on every `nfu` that moves `nixpkgs-unstable` — an unbounded recurring
  cost. The trade, accepted and named: the trust boundary widens from omp's build
  recipe to upstream's release CI (hash-pinned, nobody re-derives). Fallback is one
  line — `package = omp.packages.${pkgs.stdenv.hostPlatform.system}.default;` — and
  it builds its toolchain deps locally, because **no substituter is trusted for
  it** ([common.nix](../modules/nixos/common.nix): omp advertises nix-community's
  cache via `nixConfig`, but that is only a prompt, and machine-level trust would
  cover every store path on every host for a cache nothing here consumes).
- **Lockfile cost, accepted**: omp's inputs add `bun2nix`, `nix-bun` and
  `oxalica/rust-overlay`. `omp.inputs.nixpkgs.follows = "nixpkgs-unstable"` keeps a
  second nixpkgs out of the lock, and `omp.inputs.nixpkgs-darwin-x64.follows =
  "nixpkgs"` avoids a third for a platform no host here is on.
- **Where settings live**: `~/.omp/agent/config.yml` (main, HM-owned writable
  copy), `<cwd>/.omp/config.yml` (project overrides), `agent.db`
  (auth/sessions/MCP OAuth), `mcp.json`, logs under `~/.omp/logs`. `omp config
  path` prints the active agent dir; `PI_CODING_AGENT_DIR` relocates it (herdr's
  omp integration honors the same variable).
- The omp `browser` tool (Chromium automation) is unwired — its browser daemon
  needs `PUPPETEER_EXECUTABLE_PATH` pointed at a real Chromium, since the bundled
  Puppeteer download cannot work on NixOS. Search does not need it. Wiring Brave in
  is a trial item if omp ever becomes primary.
- `nix run github:can1357/oh-my-pi` is **ephemeral** — no GC root, swept by
  `ngca`; the installed binary from the module is the permanent path.
- Skills: `~/.agents/skills/` loads by default — omp treats `.agents/skills` as
  its canonical location, zero config.

## See also

- [doc/herdr.md](herdr.md) — the herdr adoption (same flake pattern); owns the omp
  extension asset
- [modules/home/opencode.nix](../modules/home/opencode.nix) — the first agent;
  holds the MCP block this module mirrors
- [doc/adopting-tools.md](adopting-tools.md) — the ladder this followed
- [doc/workflow.md](workflow.md) — rebuild aliases, release cycle
- upstream docs: [omp.sh/docs](https://omp.sh/docs)
