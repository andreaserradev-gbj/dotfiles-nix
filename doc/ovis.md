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
| the manifest's launcher commands | Nix, at build time | `["sh","scripts/with-bun.sh",…]` is rewritten to `${bun}/bin/bun` in the store copy; the vendored [config/ovis/ovis-herdr-plugin.toml](../config/ovis/ovis-herdr-plugin.toml) stays pristine and `nfb` re-fetches it with the pin |
| `~/.config/ovis/` | runtime state | written by the server on first start — see "State files" below |
| `~/.local/state/herdr/plugins/devswha.ovis/` | runtime state | `server.log` and `server.pid`, written by the plugin launcher under the state dir herdr gives it |
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
| `nodeModulesDev` | 441 MiB x86_64 / 434 MiB aarch64 | build-only: `vite` and the client's own dependencies |
| `nodeModulesProd` | 2.0 MiB | shipped: `jsonc-parser`, `qrcode-generator`, `web-push` |
| final plugin root | 43 MiB | `dist` 37 + `server` 3.5 + `node_modules` 2.0 + `bin` 0.53 + `shared` 0.28 + `scripts` 0.05 |

The production tree is a **hand-written allowlist**, not `bun install
--production`: that keeps every runtime dependency and resolves to 302 MiB, of
which the server and the built client load nothing. The list lives in
[config/ovis/runtime-deps.json](../config/ovis/runtime-deps.json) so that
`nfb` and the derivation read one copy; it is gated, because a hand-written list
drifts.

The gate is `bun build` over every entry point the manifest can launch
(`scripts/plugin*.ts`, `server/{index,managed,supervisor}.ts`) **against the tree
that ships**. It exits non-zero and names the missing package and importing file
when the allowlist is short. Two things about it are load-bearing:

- It must run **after** the dev tree is swapped for the prod tree. A gate run
  against the dev tree resolves everything and can never fail — that bug was
  written and caught here.
- `scripts/plugin.ts` is in scope because it imports `qrcode-generator`, which a
  `server/`-only check misses. That miss was real: a `server/`-only allowlist
  broke `plugin.ts status` at runtime.

`@pierre/diffs` is deliberately absent. The client imports it, but Vite bundles
it into `dist/`; only `server/repo-diff.test.ts` resolves it, and the gate
passes without it.

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

### The manifest's `[[build]]` entries are inert here

The substitution rewrites **every** `["sh", "scripts/with-bun.sh", …]` occurrence —
three `[[build]]`, one `[[startup]]`, three `[[actions]]` and one `[[panes]]`. What
survives untouched are the entries that name a script this build does not ship:
`scripts/preflight.sh`, `scripts/preflight.ps1` and `scripts/plugin.ps1` (the
powershell forms). So the manifest still carries seven `[[build]]` entries, three of
them naming a path absent from the store root. They cannot run:

- `herdr plugin link` parses the entries and never executes them (measured: a
  build entry that touches a file creates nothing on link).
- `herdr plugin update` refuses a linked plugin outright — `plugin is locally
  linked and cannot be updated` — so there is no update path that would run them.

If a future herdr version did run them, they would fail loudly on the missing
script rather than half-succeed. Stripping the block instead was rejected: a TOML
block-skipper in `installPhase` would have to parse the manifest, and the
assertions that matter (`id`, `version`, `min_herdr_version`, no `with-bun.sh`)
are already there.

### `bun` comes from `nixpkgs-unstable`

Pinned 26.05 ships 1.3.13, and upstream's `scripts/preflight.sh` rejects
`0.*` and `1.[0-3].*`; unstable ships 1.4.2. It is the interpreter named by
absolute path in the manifest, so a stable `bun` would be rejected at install
time. Threaded through `home-manager.extraSpecialArgs` and referenced **only**
inside the dev gate — the rule at the bottom of [flake.nix](../flake.nix).

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
of seconds. The dev tree is per-arch and genuinely differs (441 vs 434 MiB,
different native bindings), so both are measured even from a single host: the
FOD passes `--cpu=<arch>` on either host, which makes an `--cpu=arm64` install
the same tree an aarch64 host would produce.

That measurement is also reachable without a release, which matters because the
bump path only gets there once a newer tag exists and you answer `y`:

```sh
./scripts/nfb.sh --verify-ovis-hashes
```

It re-measures the source hash, both dev trees and both prod trees plus the two
arch invariants, prints `ok` or `FAIL` with both hashes, writes nothing, calls no
API, and exits non-zero on a mismatch. Run it after a hand-edited pin, or to
confirm the recorded trees still match after a `nixpkgs` change.

## Troubleshooting

| symptom | first check |
|---|---|
| `start` exits 127 mentioning `bun not found` | the manifest was not rewritten — `grep with-bun.sh` the store copy |
| `/api/health` says `terminal_attach: false` | the PTY host's record: `sha256` must equal the binary's, `version` must equal `package.json`'s |
| `server did not answer …/api/health` | `~/.local/state/herdr/plugins/devswha.ovis/server.log`, last lines |
| the plugin is missing from herdr | `herdr plugin list --json`; a failed link fails the switch, so a switch that went through linked it |
| `Serve is not enabled on your tailnet` | step 1 above |
| `Access denied: serve config denied` | step 2 above — `OperatorUser` is unset, so `extraSetFlags` did not apply; `tailscale serve reset` is the one-command test |
| a rebuild wants a new hash | `nfb`; a manual `bun install` in the wrong HOME produces a different tree |
