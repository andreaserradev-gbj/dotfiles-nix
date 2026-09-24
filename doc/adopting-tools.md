# Adopting a new tool

Tools here are adopted through the same ladder: **trial it ephemeral, promote it
through the flake only if it earns its place, never install outside the store.**
A tool's README usually opens with a `curl … | sh` installer — that is the one
path never taken here: it lands outside `/nix/store`,
invisible to generations, GC, and rollback, and it behaves differently on
every machine that runs it.

## 1. Triage — where the tool can come from

| source                 | when                                   | preferred?                                        |
| ---------------------- | -------------------------------------- | ------------------------------------------------- |
| nixpkgs                | the tool is packaged                   | **Yes** — rides the stable pin, reuses store paths |
| upstream flake         | the repo ships a `flake.nix`           | Yes — pinned, reproducible                        |
| your own derivation    | neither of the above                   | Fine — this is the normal NixOS answer            |
| upstream it to nixpkgs | long-term fix for the previous row     | Do it eventually so case 1 becomes true           |

**nixpkgs first.** Check `nix search nixpkgs <name>` or
[search.nixos.org](https://search.nixos.org) (which covers stable and
unstable). A nixpkgs package needs no new flake input, no lockfile growth, and
moves with the release cadence the repo already tracks.

**The upstream flake.** `github:owner/repo` is not something to look up — it
is constructed from the GitHub URL itself, and it is a valid flake reference
whenever the repo has a `flake.nix` at its root. Inspect it without building
anything:

```sh
nix flake show github:owner/repo      # packages, apps, overlays, modules
nix flake metadata github:owner/repo  # rev, inputs, lock state
```

Triage order: README → `flake.nix` at the repo root → `nix/` directory. What
to look for: `packages.<system>` listing your architecture, `apps.default`
(what makes `nix run` work), and any `homeManagerModules` / `nixosModules` /
`overlays` (the declarative upgrade path at promotion time).

**No flake and not in nixpkgs → write the derivation.** Typical shapes:

- Rust → `pkgs.rustPlatform.buildRustPackage` with `cargoLock.lockFile`
- Go → `buildGoModule` with `vendorHash`
- prebuilt release binary → `stdenvNoCC.mkDerivation` + `fetchurl` of the asset
  for `stdenv.hostPlatform.system`, installing the bytes as-is (`dontStrip`,
  `dontPatchELF`; the per-arch hashes are pinned in `modules/home/tool-pins.json`,
  which `nfb` bumps — `modules/home/omp-prebuilt.nix` and `herdr-prebuilt.nix`
  are the shapes to copy) — **never `autoPatchelfHook` on a static-PIE or
  Bun-standalone asset**; those patchelf traps are documented in
  [doc/omp.md](omp.md) and [doc/herdr.md](herdr.md). `programs.nix-ld` on dev
  hosts only lets *unmanaged trial* binaries run — it is not a substitute for
  packaging

Pin the source with `fetchFromGitHub` to a tag, keep the package small and
local to this repo (it then rides the normal PR → CI flow), and consider
upstreaming it to nixpkgs so next year it is simply case 1.

## 2. Trial — ephemeral, no repo changes

```sh
nix run github:owner/repo     # fetch, run, done — nothing persisted
nix shell github:owner/repo   # its default package on PATH — this shell only
```

- **Nothing is persisted.** No generation, no profile entry, no config file
  owned by the repo. `ngca` (bulk GC) reclaims the store paths afterwards.
- **Unpinned refs float.** `github:owner/repo` without a rev resolves fresh
  each time and moves daily — good enough for a trial, never a habit.
- **Never `nix profile install` as a landing place.** It mutates the user
  profile outside the flake — untracked by the repo, and left alone by every
  system rebuild and rollback. If the tool is worth keeping, promotion below
  is the path.

## 3. Promote — through the seam

First decision: **global or per-project?** Project toolchains belong in a
per-project devshell ([doc/dev-environments.md](dev-environments.md)) — the
documented global-install exceptions live there, not here. If the tool is a
project toolchain, stop here and template it instead.

A global tool lands in the dev-gated layer (`local.dev.enable`), in one of
two spots:

- **System layer** — `environment.systemPackages` in `modules/nixos/dev.nix`.
  For tools that are system-wide or service-shaped (like `opencode` or
  `ollama`).
- **Home layer** — a small HM module modeled on `modules/home/zellij.nix` (a
  flake-sourced tool adds the `imports`/`config` split of
  `modules/home/omp.nix` — step 3 below). For per-user interactive tools with
  per-user config. 100% of the module is gated `lib.mkIf
  osConfig.local.dev.enable`.

**If the tool comes from nixpkgs, that is all there is** — no flake input, no
threading. Add `pkgs.<name>` to the gated list and you are done.

**If the tool comes from an upstream flake**, three wiring steps:

1. Declare the input in `flake.nix` and name it in `outputs`' argument list —
   an input nobody destructures there is unreachable from the rest of the file:

   ```nix
   inputs.<tool>.url = "github:owner/repo";
   ```

2. Thread the flake **input** through `home-manager.extraSpecialArgs`, next to
   `user` (shape: `flake.nix`, inside `commonModules`) — HM modules cannot see
   flake inputs directly. The system layer reaches a flake value the same way
   through `specialArgs` on each `nixosSystem` — that is how `unstablePkgs`
   arrives at `modules/nixos/dev.nix`:

   ```nix
   home-manager.extraSpecialArgs = {
     inherit user;
     # the flake INPUT, not the package: the module below imports
     # mytool.homeManagerModules.default, whose package option already defaults
     # to mytool.packages.<system>.default
     inherit mytool;
   };
   ```

3. Add the HM module and import it from `home.nix` — the import belongs in that
   list unconditionally, the module gates its own `config`:

   ```nix
   # modules/home/mytool.nix — modeled on modules/home/omp.nix
   {
     lib,
     osConfig,
     mytool,
     ...
   }:
   {
     # UNCONDITIONAL on purpose: `imports` is not an option, so it cannot sit
     # behind the gate with the config below.
     imports = [ mytool.homeManagerModules.default ];

     config = lib.mkIf osConfig.local.dev.enable {
       programs.mytool.enable = true; # upstream's own HM options, if it ships any
       # No `homeManagerModules` upstream? Drop the import and take the package
       # directly: mytool.packages.${pkgs.stdenv.hostPlatform.system}.default
       # (that adds `pkgs` to the argument list above).
       # per-user config assets go in config/<tool>/…, referenced verbatim via
       # xdg.configFile — same pattern as zellij.
     };
   }
   ```

The gate is the point: `hplaptop` (dev off) evaluates the module to the empty
config, so she never sees the tool.

## 4. Verify, ship, roll back

1. `git add` everything — flakes see tracked files only, the golden rule in
   [AGENTS.md](../AGENTS.md).
2. `./scripts/check-hosts.sh` before and after. Expected: the VM (`nixos` in
   the flake's attr names) and `geekom` move; **`hplaptop` is byte-identical**
   — explain every move ([doc/workflow.md](workflow.md)).
3. PR → CI → auto-merge, per [AGENTS.md](../AGENTS.md)'s release cycle.
4. Revert is the payoff for doing it this way: `git restore --staged
   --worktree` plus one rebuild. No profile surgery, GC reclaims the store.

## Decision notes before promoting

> **A tool flake brings its own inputs.** Unless you make them follow ours
> (`inputs.<tool>.inputs.nixpkgs.follows = "nixpkgs-unstable"`, the shape of
> `flake.nix`'s `omp` input), `flake.lock` gains another nixpkgs tree — a
> second evaluation. That is the tool-flake variant of the unstable escape
> hatch in [doc/workflow.md](workflow.md): acceptable for small, userland,
> low-blast-radius tools; weigh it against the criteria documented there.

> **Check for a self-updater.** A tool that replaces its own binary fights Nix
> ownership — find the off switch in its config before adopting
> (`autoupdate = false` in `modules/home/opencode.nix`). Where the updater is
> inert under Nix — the store binary cannot replace itself — what still needs
> flipping is the phone-home/version check ([doc/herdr.md](herdr.md),
> [doc/omp.md](omp.md)).

> **Check for overlap.** A new tool may shadow an existing module's role (a
> second terminal multiplexer vs `zellij`, a second coding agent vs
> `opencode`). Trial both, keep one module per role.

> **Pin the input when the pace is wrong.** An unpinned `github:` input moves
> on every `nfu`. When a tool's release pace does not suit the system's, pin
> a tag in the URL (`github:owner/repo?ref=v1.2.3` — `flake.nix`'s `omp` input).
> Nix's flake parser forbids interpolating that `?ref=`, so it stays a literal
> that `nfb` (`scripts/nfb.sh`) rewrites, together with the version and hashes
> in `modules/home/tool-pins.json`.

---

- Promotion release cycle (PR, CI, `verified`): [AGENTS.md](../AGENTS.md);
  CI and `verified` mechanics: [doc/workflow.md](workflow.md)
- Global vs per-project rule: [doc/dev-environments.md](dev-environments.md)
- Common failure modes: [doc/troubleshooting.md](troubleshooting.md)