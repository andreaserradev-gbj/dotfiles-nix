# The dendritic pattern — features, seams, and the import-order property

This repo organizes its Nix configuration by **feature**, not by path: a feature
owns the modules that configure it, the option that switches it on, and the
place its files live. The seams that make that possible already exist here as
`local.*` options, so the pattern here is mostly a matter of naming them and
giving them a home. The hard part is not the naming — it is that **the order
in which modules are imported is load-bearing for `drvPath`**, a property this
repo's blast-radius model depends on but does not otherwise name. The
[workflow](workflow.md) doc owns the rebuild cycle, and the README's
[model section](../README.md#the-model) owns the two-layer split this pattern
sits on top of.

## What the pattern is

Organize the configuration by feature, so that a host imports a **feature by
name** rather than a pile of file paths, and one feature may contribute to
both module classes (the NixOS system layer and the Home Manager layer) at
once.

The canonical shape is a **seam module**: a module that *defines* an option
and *consumes* it.

```nix
# modules/nixos/dev.nix — the canonical seam
{
  config,
  lib,
  ...
}:
let
  cfg = config.local.dev;
in
{
  options.local.dev.enable = lib.mkEnableOption "developer tooling";

  config = lib.mkIf cfg.enable {
    # … the feature's actual configuration
  };
}
```

Five such seams exist today, all under `local.*` — this repo's own option
namespace, which nothing upstream owns:

| seam | option | consumed by |
|------|--------|-------------|
| desktop | `local.desktop.{enable,session,libreoffice.enable}` | 2 Home Manager modules, 2 host files |
| dev | `local.dev.enable` | 15 Home Manager modules |
| gaming | `local.gaming.enable` | host files only |
| docker | `local.docker.enable` | host files only |
| loopback-rebuild | `local.loopbackRebuild.{enable,authorizedKey,hostKey}` | `modules/home/shell.nix` |

The `cfg = config.local.<name>;` let-binding and the `lib.mkIf cfg.enable`
gate are the house shape; reuse them unchanged.

> **A seam defines its option and consumes it in the same file.** That is what
> makes the option visible everywhere. A module that only consumed
> `local.dev.enable` would leave the hosts that never set it unable to *turn
> it off* — the option would not exist, and the module system would fail with
> `error: The option 'local.dev' does not exist` rather than a "not enabled"
> state.

## Why this repo adopts it

The `modules/` vs `hosts/` split is already per-feature in spirit — it exists
to express blast radius, not file type — but it is **per-path in fact**. A
feature that straddles the two directories has no single home, and the reader
has to know both halves to understand it.

Two features are split today:

- **desktop** — the NixOS half in `modules/nixos/desktop.nix` (214 lines) and
  the Home Manager half in `modules/home/desktop.nix` (158 lines), plus the
  niri-only theming in `modules/home/gtk.nix` (40): 412 lines across two
  directories.
- **niri** — the session's NixOS half scattered through
  `hosts/geekom/default.nix` and its Home Manager half in
  `modules/home/niri.nix` and `modules/home/mime.nix`.

The payoff is deliberately narrow, and worth stating plainly: a registry gives
**stable feature names** and **one place that knows where a feature lives**.
It does not merge a feature's two halves into one file — that is a different
change, with a different cost, measured in [the section below](#the-two-halves-stay-in-separate-files).

## Feature registered ≠ option visible

These are two different facts, and conflating them breaks a host in a way that
is easy to misread.

- **Registered** — the feature is in the registry, so a host *can* import it.
- **Option visible** — the module that *defines* `local.<name>` is in that
  host's module set, so the host can *set* the option.

A host that cannot see an option cannot set it to `false`. So every seam
module stays in `commonModules` — including the ones only one host switches
on — because that is where the option is defined. `modules/nixos/gaming.nix`
is imported by `hplaptop` and the VM even though neither enables it.

The cross-class case is the same fact seen from the other side. A Home Manager
module reads the NixOS option through `osConfig`, which the
`home-manager` NixOS module auto-injects — 17 Home Manager modules read
`osConfig.local.*` today. The seam does not need to know about Home Manager at
all; the option is the whole interface.

> **The registry must not decide what a host can see.** It names where a
> feature lives; the import lists decide which features each host gets. If a
> registry entry were dropped from `commonModules` while a host still set
> `local.desktop.enable`, evaluation would fail with `error: The option
> 'local.desktop' does not exist` — a missing *definition*, not a disabled
> feature.

## The import-order property

> **The order in which modules are imported is load-bearing for `drvPath`.**
> A refactor that changes the import graph's *shape* — or the order of
> list-valued contributions — moves `drvPath`s with **zero content change**.
> Such a move is acceptable only when it is *named*.

This is the finding that shapes every other decision in this repo, so it is
worth stating precisely. Measured against this repo at `nixos-26.05`:

1. The module system computes the final module list with
   `builtins.genericClosure` — a Nix **builtin**, breadth-first — at
   `lib/modules.nix:570`.
2. `lib.types.listOf` (`lib/types.nix:743-790`) concatenates the list-valued
   contributions of an option **in that order**.
3. `environment.systemPackages` has six contributors in this repo
   (`modules/nixos/common.nix`, `desktop.nix`, `dev.nix`, `gaming.nix`,
   `docker.nix`, and `hosts/geekom/default.nix`), so its order is what
   changes when the graph's shape changes.
4. That order propagates: `environment.systemPackages` → `system.path`'s
   `paths` → `system.path` → `dbus-1` → `system.build.etc` → the toplevel
   derivation.

Each link is a real dependency edge in the store, not an inference: the
`system-path` derivation lists `dbus-1` among its input derivations, and
`etc.drv` lists both `system-path.drv` and `dbus-1.drv`.

### The measurement

Moving `modules/nixos/common.nix` from first to last in `commonModules` —
**reordering only, not one byte of content changed** — moved all three
hosts' `drvPath`s:

| host | baseline `drvPath` | after reordering |
|------|--------------------|------------------|
| `nixos` | `90kwgvgh0ayz0qk6rf25mnxwcwj3v3n9` | moved |
| `geekom` | `mbrykk3mvwyvwilvvma9wspxd82nipi8` | moved |
| `hplaptop` | `wf3p6s88ggsrc4czfyy0kssf5c19qr05` | moved |

geekom's `environment.systemPackages` came out the same 195 packages in a
different order — the first eight from
`["Vial-0.7.5","noctalia-5.0.1","noctalia-greeter-1.3.1","xwayland-satellite-0.8.3","slurp-1.5.0","nodejs-24.21.0","jq-1.8.2","uv-0.11.21"]`
to
`["Vial-0.7.5","noctalia-5.0.1","noctalia-greeter-1.3.1","xwayland-satellite-0.8.3","slurp-1.5.0","vim-9.2.0541","wget-1.25.0","git-2.54.0"]`.
Same set, same 195 entries, different order — and a different `system.path`,
a different `etc`, a different toplevel.

A package's *position* in the list is part of the derivation's identity, so
"the same packages" is not the same derivation.

## The registry-shape decision

Four registry shapes were measured against this repo. The deciding property
is whether the shape adds a **level to the import graph**: a path is not a
module, so it adds none, and the `genericClosure` traversal is untouched.

| shape | `nixos` | `geekom` | `hplaptop` | Home Manager generations |
|-------|---------|----------|------------|--------------------------|
| A. `deferredModule` registry + an `apply` shim yielding `{ imports = [ m ]; }` | identical | **moved** | identical | all three identical |
| B. `deferredModule` registry, no shim | identical | **moved** | identical | all three identical |
| C. no registry — one wrapper module importing all six | identical | **moved** | identical | all three identical |
| D. a registry of **paths**, read as plain data | identical | **identical** | **identical** | all three identical |

> **A registry entry must be a path.** A path adds no level to the import
> graph, so the traversal and every `drvPath` derived from it are unchanged. A
> module — or a `deferredModule`, or a wrapper — adds one, and that extra level
> reorders the list-valued contributions.

Shape D is the only one that leaves the whole fleet byte-identical, and it
needs no module system at all: the registry is a plain Nix attrset, read as
data, with no `lib.evalModules`, no `deferredModule`, no `apply` shim, and no
new flake input or lock node.

### The flat-splice rule

A list-valued entry is a **different** failure from a level added — and it is
not a silent one:

```
error: Module imports can't be nested lists. Perhaps you meant to remove one
level of lists? Definitions:
- In `/nix/store/…-source/flake.nix':
    [
      /nix/store/…-source/modules/home/niri.nix
      /nix/store/…-source/modules/home/mime.nix
    ]
```

So a list-valued registry entry must be **spliced flat** with `++` at the
position it replaces, never nested inside the import list.

## The two halves stay in separate files

> **Merging a feature's NixOS half and its Home Manager half into one file
> moves `drvPath`s.** Merging `modules/home/zellij.nix` into
> `modules/home/starship.nix` at the same import position moved `nixos` and
> `geekom`; `hplaptop` stayed byte-identical, because a dev-gated package
> ordering is not enough to change its `system.path`.

A `home`-alias bridge — one file carrying both halves, imported at both the
NixOS position and the Home Manager position and dispatching on `_class` — is
an **extra import level** for the same reason: the file is imported twice,
under two different module systems, and the contributions land in a different
position. Measured, the bridge moved `geekom` **and** `hplaptop`, and two of
the three Home Manager generations.

So the adoption is bounded, and the bound is the honest part:

> **A `drvPath`-preserving adoption names features and centralizes their
> location. It does not merge the two halves of a feature into one file.**

Merging is a separate change, with a named `drvPath` move in its commit
message — the repo's own rule that a move you cannot name is the failure.

## Adding a feature

The recipe for the registry layout this doc describes:

1. Create `features/<name>/` and put the feature's modules there — one file
   per module class, at the same depth as the modules they replace.
2. Add the registry entry: a **path** for a single module, a **list of paths**
   for several.
3. Import it by name — from `commonModules` in `flake.nix` for a shared
   feature, or from the host file for a host-specific one. Keep the seam
   module in `commonModules` even if only one host enables it, so the option
   stays visible everywhere.
4. Run the registry check, then `./scripts/check-hosts.sh` and compare against
   the recorded baseline. A host that moved without a named reason is a
   regression, not a curiosity.

## See also

- [README.md](../README.md) — the two-layer model and the blast-radius rule
  this pattern refines
- [doc/workflow.md](workflow.md) — the rebuild cycle and the `drvPath`
  comparison discipline
- [doc/adopting-tools.md](adopting-tools.md) — how a tool becomes a feature
- [doc/niri-session.md](niri-session.md) — the niri feature, the second of the
  two split features
- [modules/nixos/dev.nix](../modules/nixos/dev.nix) — the canonical seam
- [modules/nixos/desktop.nix](../modules/nixos/desktop.nix) — a seam with a
  typed and a nested sub-option
- [modules/home/desktop.nix](../modules/home/desktop.nix) — the Home Manager
  half of a seam, gated on the same option
- upstream: [the dendritic pattern](https://github.com/mightyiam/dendritic)
