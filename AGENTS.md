# AGENTS.md — orientation for AI agents working in this repo

One flake, three hosts (`nixos` = aarch64 UTM VM, `geekom` and `hplaptop` =
x86_64), two layers (system + Home Manager) built by one `nixos-rebuild`.
Start from the [README](README.md) for the model and the
[documentation index](README.md#documentation-index) for task-specific depth.

## Golden rules — violating any of these breaks the build or the machine

1. **`git add` before any `--flake` command.** Flakes only see git-tracked
   files; an untracked new module is invisible to evaluation and the error
   reads "path does not exist," not "you forgot to stage."
2. **Never touch `system.stateVersion` / `home.stateVersion`.** They are one-way
   migration-semantics flags pinned at install time, not release indicators.
   Upgrading the NixOS release never changes them
   (see [doc/workflow.md](doc/workflow.md), "Upgrading to a new NixOS release").
3. **Blast radius: `modules/` moves every host; `hosts/<host>/` moves one.**
   Before editing a shared module, run `./scripts/check-hosts.sh` and record
   the printed `drvPath`s; after editing, run it again — a host you did not
   mean to touch must not move.
4. **`nix flake check` does not evaluate `nixosConfigurations`.** The gate is
   `./scripts/check-hosts.sh`, and its untracked-file warning comes first for a
   reason: a green result on a stale tree is worse than a red one.

## Working rules

- **Comments are load-bearing.** This repo documents *why* — e.g. why geekom
  uses `ollama-vulkan` with `OLLAMA_IGPU_ENABLE`, why `boot.loader.efi`
  can't touch NVRAM on the VM, why suspend stays masked on `geekom` (no S3;
  hplaptop was verified clean and unmasked — see
  [doc/bare-metal-hplaptop.md](doc/bare-metal-hplaptop.md)).
  Read the surrounding comments before changing anything; preserve and extend
  them when the reasoning changes. Do not "clean up" a comment you have not
  understood — `"Did you read the comment?"` in `hosts/vm/default.nix` is
  aimed at exactly that mistake.
- **Assets are verbatim.** `config/<tool>/…` is copied, not templated — edit the
  file itself, not a generator (there is none).
- **Formatting** is `nixfmt` via `nix fmt` (pre-commit hook installed by
  `.envrc` runs it too).
- **Language** for all docs and comments: English.
- **Library/API docs via context7.** When a task needs library, tool, or API
  documentation, use the `context7` MCP tools (resolve the library, then query
  its docs) instead of relying on training data — the config lives in
  `modules/home/opencode.nix`.

## Task routing

| task                                        | read first                                      |
| ------------------------------------------- | ----------------------------------------------- |
| rebuilds, updates, generations, GC         | [doc/workflow.md](doc/workflow.md)              |
| release upgrade (26.05 → 26.11 …)           | [doc/workflow.md](doc/workflow.md)              |
| new machine install                         | [doc/install-vm.md](doc/install-vm.md) + the bare-metal docs |
| per-project dev shells                      | [doc/dev-environments.md](doc/dev-environments.md) |
| VM console / boot fallbacks                | [doc/vm-console.md](doc/vm-console.md)          |
| something behaves unexpectedly              | [doc/troubleshooting.md](doc/troubleshooting.md) |

## Verification before claiming success

1. `git add` the changed files.
2. `./scripts/check-hosts.sh` — every host must still evaluate, and the
   `drvPath` deltas must match your intent (shared change → all hosts move;
   host change → exactly one moves).
3. Docs changed? Check every `](...)` link resolves and keep files under
   ~500 lines (split when a doc grows past that).
4. Push issued? `.github/workflows/ci.yml` builds `geekom` and `hplaptop` from
   GitHub, and `hplaptop` updates itself unattended from `main` (`nrb` with
   `--refresh`). A commit that fails CI must not be merged or sit on `main` —
   the next `nrb` on that machine would install it.
