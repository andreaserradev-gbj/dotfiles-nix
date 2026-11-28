# ovis — the browser and phone client for herdr

Ovis ([github:devswha/ovis](https://github.com/devswha/ovis)) serves a chat and
live-terminal UI for every herdr agent pane on `127.0.0.1:7317`, and the same UI
on a phone over the tailnet. It was promoted into the flake as a dev-gated
home-layer plugin via the [adoption ladder](adopting-tools.md).

**Status: adopted on dev hosts** (`geekom`, the dormant `nixos` VM; hplaptop is
not a dev host). The version that runs is the version reviewed: upstream ships
no server asset, so the plugin is built from the pinned tag rather than
installed by herdr.

Why not `herdr plugin install`: that clones `main` **and executes its build
commands as you**. A link at a store path keeps the running bytes immutable and
reviewable, which is the same trade herdr itself makes.

## Ownership: Nix-managed vs manual/stateful

[modules/home/ovis.nix](../modules/home/ovis.nix) wraps its whole body in
`lib.mkIf osConfig.local.dev.enable`; `hplaptop` evaluates it to the empty
config.

| artifact | owned by | how it gets there |
|---|---|---|
| plugin root (Bun server, built client, runtime deps, Rust PTY host) | Nix | built from the pinned tag by [ovis-prebuilt.nix](../modules/home/ovis-prebuilt.nix); version, source hash, both dependency trees and the PTY-host hash from the `ovis` entry in [tool-pins.json](../modules/home/tool-pins.json) |
| `~/.config/herdr/plugins/config/devswha.ovis/env` | Nix | `xdg.configFile`, a store symlink to the verbatim asset [config/ovis/env](../config/ovis/env) |
| herdr plugin registry entry (`devswha.ovis`) | Nix | `home.activation` runs `herdr plugin link` on the store path every switch — the [reviewr](herdr.md) pattern |
| the manifest's commands | Nix, at build time | `["sh","scripts/with-bun.sh",…]` becomes `${bun}/bin/bun`, `scripts/plugin-launch.ts` becomes `scripts/plugin.ts`, and the `[[build]]` entries are dropped; the vendored [config/ovis/ovis-herdr-plugin.toml](../config/ovis/ovis-herdr-plugin.toml) stays pristine and `nfb` re-fetches it with the pin |
| `~/.config/ovis/` | runtime state | written by the server on first start — see "State files" below |
| `~/.local/state/herdr/plugins/devswha.ovis/` | runtime state | `server.log` and `server.pid`, written by `scripts/plugin.ts` under the state dir herdr gives it |
| the autostart hook | Nix, upstream | the plugin's `[[startup]]` entry runs `scripts/plugin.ts start` once per herdr start; herdr is a session-scoped user unit ([herdr.md](herdr.md)), so ovis comes up with the session and nothing new supervises anything |

**Nothing writes back into the store.** The plugin root is read-only, and that is
deliberate: the update checker runs `git rev-parse HEAD`, fails because there is
no `.git`, and sets `managed: false` with
`Updates require a Git checkout on the main branch.`
([server/updater.ts:226](https://github.com/devswha/ovis/blob/v0.4.18/server/updater.ts)).
Every later tick returns on the first line of `request()`, so it is a no-op
rather than a failing retry — no git spawn, no network, nothing logged. Settings
→ About hides the Check/Update controls. `nfb` is the only update path.

One unrelated GitHub call exists and is not the updater: `server/usage.ts`
queries `api.github.com/copilot_internal/user` for Copilot quota *when a Copilot
pane is being used and you have that CLI configured*. It is upstream behaviour,
unchanged by this deployment; if you never use Copilot it never runs.

## Configuration surfaces

Four places can carry settings. Only one is Nix-ownable without a credential
problem.

| surface | who writes it | note |
|---|---|---|
| `env` in the plugin config dir | **Nix** (store symlink) | the right place for non-secret settings; this is where `OVIS_TELEMETRY=0` lives |
| `.env` in the same dir | you, by hand | read after `env`, so it wins. For experiments you do not want to commit — and it survives a switch only because Nix does not own it |
| Settings → Devices / Preferences in the UI | the server | pairing state and UI preferences, under `~/.config/ovis/` |
| shell environment | whatever started herdr | inherited by the plugin; last resort, invisible to a later reader |

**The env file holds no credential, and must never hold one.** It is a symlink
into `/nix/store` (0444) from a public repository, so anything in it is
world-readable and published. A token, if ever wanted, takes the
`sops.templates` route at the same path with mode `0400`, replacing the
symlink; the PRD's deferred table records that route rather than building it.

`OVIS_TELEMETRY=0` is the one setting that ships. It silences install and update
events plus a daily "active" message naming which agent kinds run — the only
outbound traffic besides the (dead) update check. `DO_NOT_TRACK=1` has the same
effect.

**Reading telemetry state takes two fields.** `/api/telemetry` returns
`enabled` (the UI switch, persisted in `telemetry.json`) and `blocked_by_env`
(the environment gate). `report()` returns before any request when
`blocked_by_env` is true, so `"enabled": true` in the file is not evidence of
traffic — check `blocked_by_env`.

## Access model

The server binds `127.0.0.1`. `decideAccess`
([server/access.ts](https://github.com/devswha/ovis/blob/v0.4.18/server/access.ts))
is ordered and first-match-wins:

| # | condition | result |
|---|---|---|
| 1 | token matched | full |
| 2 | paired-device cookie | full (a watch-only device cannot type) |
| 3 | `OVIS_TOKEN` configured | refuse everything else, loopback included |
| 4 | loopback + `Tailscale-User-Login` + owner known + `X-Forwarded-For` in the tailnet | full if the login is the owner, else `other_user` |
| 5 | serve-only proof (`OVIS_TAILSCALE_SERVE_ONLY=1`, one login, no tagged node, Host names this node) | full |
| 6 | loopback, not proxied | full — this PC |
| 7 | loopback but proxied, and owner known / tagged / serve-only | pairing required |
| 8 | **unpaired and not funnel** | **full — open to anything that reaches the port** |
| 9 | otherwise | pairing required |

This deployment lands on rows 1, 2 and 6 today: the bind stays `127.0.0.1`, no
token is set, and nothing forwards to the port, so row 8 is unreachable. Row 4
is what `tailscale serve` exercises once it is enabled: your phone sends your
tailnet login, it matches the node owner, and the browser gets in with no
pairing code.

The one thing to remember: **row 8 is real.** If you ever change `HOST` to
`0.0.0.0`, put `tailscale serve` in front, or set a token, an unpaired caller on
the same network gets a drive-level session. The bind is the safety, not the
access table.

## State files

| path | contents |
|---|---|
| `~/.config/ovis/completions.json` | the `/`-command completion cache |
| `~/.config/ovis/telemetry.json` | install id, the UI switch, the notice marker |
| `~/.config/ovis/http-requests.jsonl` | the request log the UI's diagnostics read |
| `~/.config/ovis/bridges/*.json` | one bridge record per paired device, `+ .guard` |
| `~/.config/ovis/devices.json` | the pairing registry: paired devices and `gateClosedAt`. **Its presence is what closes the access gate** — delete it and row 8 reopens on the next start |
| `~/.config/ovis/updates/<id>/supervisor.lock/` | the single-supervisor lock (`owner.json`, `pid`) |
| `~/.local/state/herdr/plugins/devswha.ovis/server.log` | the server's stdout/stderr — **first place to look when it will not start** |
| `~/.local/state/herdr/plugins/devswha.ovis/server.pid` | the launcher's pid record |

Safe to delete the whole of `~/.config/ovis` on a clean re-install: it costs the
pairing, the preferences and the install id, nothing else. `server.log` is worth
reading before deleting anything.

**The one deletion with a security consequence is `devices.json`.** The gate is
closed while that file holds a device or a `gateClosedAt` (`server/devices.ts`,
`get gated`), which is the `gated` flag in access row 8. Delete it and the next
start is an ungated store, so an unpaired caller that can reach the port gets a
drive-level session. Harmless today because the bind is `127.0.0.1`; not harmless
if you ever set `HOST=0.0.0.0` or put a proxy in front.

## Build shape

Two fixed-output derivations supply dependency trees, because a sandboxed
derivation has no network and `bun install` needs it; FODs are the only class
Nix exempts from the network namespace.

| tree | size | role |
|---|---|---|
| `nodeModulesDev` | 459 MiB x86_64 / 451 MiB aarch64 | build-only: `vite` and the client's own dependencies |
| `nodeModulesProd` | 5.4 MiB | shipped: `jsonc-parser`, `qrcode-generator`, `web-push`, `tweetnacl`, `base64-js`, `@noble/hashes`, `@noble/curves`, `@noble/ciphers`, `@sindresorhus/slugify` |
| final plugin root | 62 MiB | `dist` 43 + `server` 9 + `node_modules` 5 + `shared` 3 + `tui` 1 + `bin` 1 + the rest <1 |

**What ships is what the entry points load.**
[ovis-shipped-files.ts](../modules/home/ovis-shipped-files.ts) walks that the
way Bun resolves it, and the derivation installs the list and nothing else of
the source. Two kinds of edge: an import — static, or a dynamic import whose
specifier is a literal — and a path written as a string literal that is no
import, because `server/file-pool.ts` starts its worker with
`new URL("./file-worker.ts", import.meta.url)`, which no import reaches.
Packages are left to the allowlist below; so are tests, fixtures, the
browser-QA scripts, and the client's `src/` except the files under `src/lib`
the plugin scripts reach — none of the rest is something the plugin can load.

The bundler's module list is not the same thing, and was the alternative: its
source map carries neither the two files `server/approvals/cmd.ts` loads from
`integrations/` as text, nor a module whose exports the bundle tree-shook away
while the runtime still loads the file.

Beside the list, by hand and each for a reason: `dist/` (the Vite build), the
prod `node_modules/`, `package.json`, `bunfig.toml` and `tsconfig.json` (what
Bun reads at start-up), the licences, and `scripts/plugin.ps1`, the Windows
launcher the manifest names.

The production tree is a **hand-written allowlist**, not `bun install
--production`: that keeps every runtime dependency and resolves to 302 MiB, of
which the server and the built client load nothing. The list lives in
[config/ovis/runtime-deps.json](../config/ovis/runtime-deps.json) so that
`nfb` and the derivation read one copy; it is gated, because a hand-written list
drifts.

There are **three** checks, and they fail on different mistakes:

- In `buildPhase`, over the prod dependency tree: `bun build` proves the
  allowlist is complete. `scripts/plugin.ts` is in scope because it imports
  `qrcode-generator`, which a `server/`-only check misses — a `server/`-only
  allowlist really did break `plugin.ts status`.
- In `installPhase`, over `$out`: the same `bun build`, so it proves the *copy*
  is complete — a module the walk missed fails the build and names itself.
- In `installPhase`, over the rewritten manifest: every `scripts/`- or
  `server/`-path a command names must exist in `$out`. `bun build` follows
  imports, not manifest strings, so it cannot see this one.

The last two exist because a green build once shipped a plugin whose manifest
pointed at `scripts/plugin-launch.ts`, a file the store did not contain: the
gate covered packages only, and every command died after a successful link.

All of them run **after** the dev tree is swapped for the prod tree. A gate run
against the dev tree resolves everything and can never fail — that bug was
written and caught here.

The entry points both `bun build` gates bundle, and the walk starts from, are
read at build time from upstream's own table — `ENTRIES`, in
`server/entries.ts` — not copied into the derivation: a copy has no gate, so an
entry upstream added between tags would ship a tree that cannot launch it, with
a green build.

`@pierre/diffs` and `react` are deliberately absent. The client imports both and
Vite bundles them into `dist/`; only tests and the browser-QA fixtures under
`scripts/` resolve them, and the gate passes without them.

### Three build traps

1. **Any build in a read-only tree fails.** Vite writes `node_modules/.cache`
   (the compiled xterm source) and `dist/`, and a store input is read-only. The
   build runs in a writable copy with `chmod -R u+w node_modules`.
2. **Vite is invoked by path, not through `.bin`.** `node_modules/.bin/vite` is a
   symlink; a path names no symlink, so it cannot become the thing that breaks
   when the tree's permissions differ. (Both forms work on a writable tree —
   measured — so this is defence, not a fix.)
3. **`node` is not needed.** `bun --bun node_modules/vite/bin/vite.js build` runs
   vite's `#!/usr/bin/env node` shebang itself. Adding `nodejs` to
   `nativeBuildInputs` does not help and is not required.

### The Rust PTY host

Upstream's static musl sidecar ships as `bin/ovis-pty-sidecar` with a record
beside it, `{"crate":null,"sha256":"…","version":"0.4.18"}`.
`installedHostVouched` compares **only** `sha256` and `version`, which is why
`crate` can be null here (`crate` belongs to the installer's source-match check,
never to the runtime). With the host in place `/api/health` reports
`terminal_attach: true` and the log's first line is `PTY host: Rust`.

The Node fallback is not shipped: it would add `@lydell/node-pty` **and** a real
Node, and upstream marks the arm64 `node-pty` "not tested". If the host ever fails
its probe, panes fall back to mirrored repaints and the log says
`PTY host: none … panes are mirrored`.

### The manifest is rewritten to run `scripts/plugin.ts`

Two upstream shapes are undone on the way into the store, by
[rewrite-ovis-manifest.ts](../modules/home/rewrite-ovis-manifest.ts):

- **The launcher is repointed.** Upstream's commands run
  `scripts/plugin-launch.ts`, a *source-checkout* entry point: it installs the
  release's server into `$root/.ovis/server` before running anything. A store
  path is read-only, so every one of its commands died with
  `EROFS: read-only file system, mkdir '…/.ovis'` — herdr's own startup log,
  exit 1. `scripts/plugin.ts` needs nothing writable under the root: it runs the
  tree in place and keeps state under `HERDR_PLUGIN_STATE_DIR`. It is what
  0.5.3's manifest called, before upstream moved to the launcher.
- **The `[[build]]` entries are dropped.** They are the checkout's own installer
  (preflight, then `plugin-launch.ts install`) for a tree Nix already built, and
  herdr runs build entries only when it installs a plugin from a source — never
  for `plugin link` (measured: a linked probe plugin's build entry never ran).
  They could only fail, and after the repoint they would name a file that is no
  longer shipped.

`plugin.ps1` embeds the launcher path itself, so it is rewritten too. The build
fails if either rewrite missed (`grep plugin-launch`, `grep '^\[\[build\]\]'`)
or if the shipped manifest names any `scripts/`- or `server/`-path that does not
exist in `$out`.

The vendored [config/ovis/ovis-herdr-plugin.toml](../config/ovis/ovis-herdr-plugin.toml)
stays byte-identical to the tag — that is what `nfb` diffs and re-fetches; the
rewrite happens only in the store copy.

The `.sh`/`.ps1` launcher helpers (`with-bun.sh`, `preflight.*`,
`plugin-launch.ts`, `server-install.ts`, `server-manifest.ts`, `pty-sidecar.ts`)
are not shipped at all: nothing the manifest runs reaches them.

### `bun` comes from `nixpkgs-unstable`

Pinned 26.05 ships 1.3.13, and upstream requires 1.4 or newer (its
`scripts/preflight.sh` rejects `0.*` and `1.[0-3].*`); unstable ships 1.4.4. It
is the interpreter named by absolute path in the manifest **and** the one that
builds the client, so a stable `bun` would fail either way. Threaded through
`home-manager.extraSpecialArgs` and referenced **only** inside the dev gate — the
rule at the bottom of [flake.nix](../flake.nix).

## Tailnet runbook

Getting a phone in. One prerequisite is manual and one-time, and the server
cannot do it for you: the nixpkgs module has no option for the tailnet's Serve
setting. The operator half — which used to be a manual `tailscale set` — is now
Nix-owned ([hosts/geekom/default.nix](../hosts/geekom/default.nix),
`services.tailscale.extraSetFlags`).

**1. Enable Serve for the tailnet** — admin console, once per tailnet. Without
it, the command in step 2 answers `Serve is not enabled on your tailnet` and
prints a `https://login.tailscale.com/f/serve?node=…` link.

**2. Confirm the operator** — no action expected; this checks the Nix side:

```sh
tailscale debug prefs | grep OperatorUser      # → "OperatorUser": "<you>"
tailscale serve reset                          # → silent; without the operator: "Access denied: serve config denied"
```

`extraSetFlags` runs `tailscale set --operator=<user>` as root at boot, which
sets `OperatorUser`; without it a non-root `serve` **write** is refused.
Read-only `serve status` succeeds either way and is not a test of this step —
`serve reset` is, and it is harmless with no config.

Do them in this order and do not read one message as evidence about the other:
with Serve still off, `tailscale serve --bg …` answers `Serve is not enabled on
your tailnet`, and the operator refusal only appears on a `serve` write after
Serve is on. Two different blockers, one at a time.

**3. Publish the app** — repeat after a port change:

```sh
tailscale serve --bg --https=443 http://127.0.0.1:7317
tailscale serve status
```

Then open `https://<host>.<tailnet>.ts.net` on the phone. The certificate is for
the name, not the `100.x` address — opening the IP warns.

Availability follows herdr: the plugin lives inside the server, and the server is
pulled in by `graphical-session.target` ([herdr.md](herdr.md), "The unit"). So the
port answers only while a graphical session exists. Locking the screen keeps it
up; logging out (or rebooting without logging in) takes it down, and the phone
then gets a connection error rather than a pairing prompt. That is deliberate:
SSH alone needs no session, but the agents ovis shows need the keyring and the
Wayland socket, both of which only a graphical login provides.

**Phone setup inside herdr** (the `phone` action, or Settings → Phone) prints the
same command in a pane, and — when Serve is still off — says so before you run
it. It also mints a **pairing code** for one device, good for ten minutes; that
code is for getting a device in *before* Serve exists, and is not needed once
your phone's tailnet login matches the node owner (row 4 of the access table).
The action never changes Serve itself; the command it prints does.

From a shell, `herdr plugin action invoke devswha.ovis.phone` opens that pane
rather than printing to the terminal. Either way the server keeps serving
`127.0.0.1`; Serve is the only ingress.

**Undo:** `tailscale serve --https=443 off`.

**If the phone is still asked to pair:** it is sending no
`Tailscale-User-Login`, which happens behind a proxy other than `tailscaled`.
`OVIS_TAILSCALE_SERVE_ONLY=1` in the `env` file is the fallback — it trusts a
single-login, untagged tailnet whose request names this node. Only valid while
nothing else reaches the port: it weakens the login check on purpose.

The SSH layer this sits on — the LAN path, the one-time tailnet join, key
scopes — is [doc/remote-access.md](remote-access.md), unchanged by this feature.
Ovis adds a third layer above it: HTTPS to the app through `tailscale serve`.

## `nfb` and the pin

`nfb` bumps `ovis` like the other tools, with one difference: it is the only
source build, so its pin carries four values per arch instead of one asset
hash — the source tree, the dev dependency tree and the prod dependency tree
(the prod value is written to both arches because the allowlist has no
platform-specific package; `nfb` asserts that rather than assuming it).

`ovis_dep_hashes` re-measures all of them: it fetches the tag's archive,
installs both trees with the flake's own `bun`, and refuses to write if the
source hash disagrees across arches or the prod tree does. The vendored manifest
is re-fetched in the same run with `guard = '^id = "devswha.ovis"$'`.

A bump therefore costs two `bun install` runs plus one archive fetch, a few tens
of seconds, plus the plugin build itself, which `nrp` then reuses. The dev tree
is per-arch and genuinely differs (459 vs 451 MiB, different native bindings),
so both are measured even from a single host: the FOD passes `--cpu=<arch>` on
either host, which makes an `--cpu=arm64` install the same tree an aarch64 host
would produce.

**The bump is then proven before it is recorded.** `nfb` builds the plugin
derivation this host's system closure holds — looked up in the toplevel's
inputs, so it is the very one `nrp` builds — and the three gates above run at
the prompt instead of in `nrp`. A host that ships no ovis has nothing to
prove. A
gate that fails prints the last lines of the build log, which name what the tag
moved — as a rule a package missing from the allowlist. The bump stays written
(the pin is complete; it is the allowlist that needs the entry), the baseline
is not re-recorded, and `nfb` exits 1.

Both measurements copy the tag's `bun.lock` next to the rewritten
`package.json`, because the FOD installs inside the source tree and therefore
uses the lock. Leaving it out is invisible while every allowlist entry is
pinned exactly or has no newer patch; the moment one carries a caret range and
the registry publishes a patch, the measurement resolves a tree the FOD never
builds and the pin fails with a hash mismatch.

That measurement is also reachable without a release, which matters because the
bump path only gets there once a newer tag exists and you answer `y`:

```sh
./scripts/nfb.sh --verify-ovis-hashes
```

It re-measures the source hash, both dev trees and both prod trees plus the two
arch invariants, prints `ok` or `FAIL` with both hashes, writes nothing, calls no
API, and exits non-zero on a mismatch. Run it after a hand-edited pin, or to
confirm the recorded trees still match after a `nixpkgs` change.

```sh
./scripts/nfb.sh --write-ovis-hashes
```

The same measurement, **written**: for the pinned tag it rewrites ovis's entry
of the pin table, builds the plugin and — only once that holds — re-records the
baseline, as a bump does. It is the step after a bump's build failed: fix what
the log named, run it, and the prod hash follows the allowlist with no
hand-measured value.

## Troubleshooting

| symptom | first check |
|---|---|
| `start` exits 127 mentioning `bun not found` | the manifest was not rewritten — `grep with-bun.sh` the store copy |
| `start` exits 1 with `EROFS … mkdir '…/.ovis'` | the manifest still runs `scripts/plugin-launch.ts`, which wants a writable checkout — `grep plugin-launch` the store copy; [rewrite-ovis-manifest.ts](../modules/home/rewrite-ovis-manifest.ts) should have repointed it to `scripts/plugin.ts` |
| `herdr plugin log list` shows a `startup` failure | that log holds the last run's exit code and stderr; compare its `finished_unix_ms` with `date +%s` — an entry older than the last `herdr plugin link` is the previous generation's |
| `/api/health` says `terminal_attach: false` | the PTY host's record: `sha256` must equal the binary's, `version` must equal `package.json`'s |
| `server did not answer …/api/health` | `~/.local/state/herdr/plugins/devswha.ovis/server.log`, last lines |
| the plugin is missing from herdr | `herdr plugin list --json`; a failed link fails the switch, so a switch that went through linked it |
| `Serve is not enabled on your tailnet` | step 1 above |
| `Access denied: serve config denied` | step 2 above — `OperatorUser` is unset, so `extraSetFlags` did not apply; `tailscale serve reset` is the one-command test |
| `nfb` ends with `ovis … does not build` | the log lines above the message name what the tag moved, as a rule a package to add to [config/ovis/runtime-deps.json](../config/ovis/runtime-deps.json) — then `nfb --write-ovis-hashes` |
| a command dies on a missing file of the plugin root while the build stayed green | a file loaded by a computed path, which neither an import nor a literal names: add it to the hand-written data files in [ovis-prebuilt.nix](../modules/home/ovis-prebuilt.nix) |
| a rebuild wants a new hash | `nfb --write-ovis-hashes` re-measures for the pinned tag; a manual `bun install` in the wrong HOME produces a different tree |
