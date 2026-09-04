# Adopting a new tool

Every tool in this repo has followed the same ladder: **trial it ephemeral,
promote it through the flake only if it earns its place, never install outside
the store.** A tool's README usually opens with a `curl … | sh` installer —
that is the one path never taken here: it lands outside `/nix/store`,
invisible to generations, GC, and rollback, and it behaves differently on
every machine that runs it.

## 1. Triage — where the tool can come from

| source                 | when                                   | preferred?                                        |
| ---------------------- | -------------------------------------- | ------------------------------------------------- |
| nixpkgs                | the tool is packaged                   | **Yes** — rides the stable pin, reuses store paths |
| upstream flake         | the repo ships a `flake.nix`           | Yes — pinned, reproducible                        |
| your own derivation    | neither of the above                   | Fine — this is the normal NixOS answer            |
| upstream it to nixpkgs | long-term fix for the previous row     | Do it eventually so case 1 becomes true           |

**nixpkgs first.** Check `nix search nixpkgs#<name>` or
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
- prebuilt release binary → `stdenv.mkDerivation` + `fetchurl` +
  `autoPatchelfHook` (note: `programs.nix-ld` on dev hosts exists so
  *unmanaged trial* binaries can run — it is not a substitute for packaging)

Pin the source with `fetchFromGitHub` to a tag, keep the package small and
local to this repo (it then rides the normal PR → CI flow), and consider
upstreaming it to nixpkgs so next year it is simply case 1.

## 2. Trial — ephemeral, no repo changes

```sh
nix run github:owner/repo     # fetch, run, done — nothing persisted
nix shell github:owner/repo   # both on PATH for the current shell only
```

- **Nothing is persisted.** No generation, no profile entry, no config file
  owned by the repo. `ngca`-adjacent GC reclaims the store paths afterwards.
- **Unpinned refs float.** `github:owner/repo` without a rev resolves fresh
  each time and moves daily — good enough for a trial, never a habit.
- **Never `nix profile install` as a landing place.** It mutates the user
  profile outside the flake — untracked, unexplained, unrevertable by any
  generation. If the tool is worth keeping, promotion below is the path.

## 3. Promote — through the seam

First decision: **global or per-project?** Project toolchains belong in a
per-project devshell ([doc/dev-environments.md](dev-environments.md)) — the
global-install exception exists only for agent tooling and hosts-wide CLIs.
If the tool is a project toolchain, stop here and template it instead.

A global tool lands in the dev-gated layer (`local.dev.enable`), in one of
two spots:

- **System layer** — `environment.systemPackages` in `modules/nixos/dev.nix`.
  For tools that are system-wide or service-shaped (like `opencode` or
  `ollama`).
- **Home layer** — a small HM module modeled on `modules/home/zellij.nix`.
  For per-user interactive tools with per-user config. 100% of the module is
  gated `lib.mkIf osConfig.local.dev.enable`.

**If the tool comes from nixpkgs, that is all there is** — no flake input, no
threading. Add `pkgs.<name>` to the gated list and you are done.

**If the tool comes from an upstream flake**, three wiring steps:

1. Declare the input in `flake.nix`:

   ```nix
   inputs.<tool>.url = "github:owner/repo";
   ```

2. Thread the package through `home-manager.extraSpecialArgs` next to `user`
   (shape: `flake.nix`, `commonModules`) — HM modules cannot see flake inputs
   directly:

   ```nix
   # in the module that sets home-manager.* (pkgs is in scope there)
   home-manager.extraSpecialArgs = {
     inherit user;
     mytool = mytool.packages.${pkgs.system}.default;
   };
   ```

3. Add the HM module and import it from `home.nix`:

   ```nix
   # modules/home/mytool.nix — modeled on modules/home/zellij.nix
   {
     lib,
     osConfig,
     mytool,
     ...
   }:
   lib.mkIf osConfig.local.dev.enable {
     home.packages = [ mytool ];
     # per-user config assets go in config/<tool>/…, referenced verbatim via
     # xdg.configFile — same pattern as zellij.
   }
   ```

The gate is the point: `hplaptop` (dev off) evaluates the module to the empty
config, so she never sees the tool.

## 4. Verify, ship, roll back

1. `git add` everything (golden rule 1 — flakes see tracked files only).
2. `./scripts/check-hosts.sh` before and after. Expected: `vm` and `geekom`
   `drvPath`s move; **`hplaptop` is byte-identical**. Explain the move with
   `nvd diff` — the tool's store path appearing in the dev hosts' closures
   and nowhere else is the whole story.
3. PR → CI → auto-merge, per [doc/workflow.md](workflow.md)'s release cycle.
4. Revert is the payoff for doing it this way: `git restore --staged
   --worktree` plus one rebuild. No profile surgery, GC reclaims the store.

## Decision notes before promoting

> **Tool flakes cost a second nixpkgs.** An upstream flake input carries its
> own inputs (typically `nixpkgs` unstable + a rust overlay) into
> `flake.lock` — a second evaluation tree. That is the tool-flake variant of
> the unstable escape hatch in [doc/workflow.md](workflow.md): acceptable for
> small, userland, low-blast-radius tools; weigh it against the criteria
> documented there.

> **Check for a self-updater.** A tool that offers to replace its own binary
> fights Nix ownership of that binary. The repo's precedent is opencode's
> disabled auto-updater (`modules/home/opencode.nix`) — check the new tool's
> config for the equivalent knob before adopting.

> **Check for overlap.** A new tool may shadow an existing module's role (a
> second terminal multiplexer vs `zellij`, a second coding agent vs
> `opencode`). Trial both, keep one module per role.

> **Pin the input when the pace is wrong.** An unpinned `github:` input moves
> on every `nfu`. When a tool's release pace does not suit the system's, pin
> a tag in the URL (`github:owner/repo?ref=v1.2.3`).

---

- Promotion release cycle (PR, CI, `verified`): [doc/workflow.md](workflow.md)
- Global vs per-project rule: [doc/dev-environments.md](dev-environments.md)
- Common failure modes: [doc/troubleshooting.md](troubleshooting.md)