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
   the printed `drvPath`s; after editing, run it again. A move is fine when you
   can explain it: `nvd diff` between the two closures — or
   `nix store diff-closures` on a host without `nvd`, which includes
   `hplaptop` — where an empty package diff is a real explanation. A move you
   cannot name is the failure. `hplaptop` updates unattended, so she must not
   move unless you meant her.
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

## Release cycle — branch → PR → CI → squash merge → cleanup → verify on main

1. **Branch** from `main`, short descriptive name (`fix/lazygit-clipboard`
   style). A trial can run entirely uncommitted: working tree + `git add` is
   enough for flake eval (golden rule 1), and `git restore --staged
   --worktree` plus one rebuild is the whole revert. Branch and commit only
   once the change is accepted.
2. **PR** → CI: `evaluate` (the same `check-hosts.sh` gate used locally)
   plus a build matrix for exactly the hosts whose `drvPath` moved vs
   `verified`; `gate` is the single required check. Branch protection itself
   lives in the GitHub UI — see the two assumptions at the top of
   `.github/workflows/ci.yml`, which nothing in the repo can assert.
3. **Auto squash merge**: squash and auto-merge are enabled repo-wide
   (squash commit message style `PR_TITLE`). Enable auto-merge on the PR;
   GitHub squashes it the moment the gate goes green. One commit per PR
   keeps `main` bisectable.
4. **Branch cleanup is automatic**: `delete_branch_on_merge` is on, so the
   remote PR branch dies with the merge. Delete the local one by hand
   (`git branch -d <name>`). The `verified` ref is never touched — only PR
   head branches are deleted on merge.
5. **Verify on `main`**: the squash push re-runs CI, and `advance-verified`
   fast-forwards `verified` — the ref hplaptop's unattended `nrb --refresh`
   pulls ([doc/workflow.md](doc/workflow.md), `modules/home/maintenance.nix`),
   so she installs only commits CI has already built green. geekom is rebuilt
   by hand from `main`. While `main` is red, `verified` stops advancing and
   the laptop silently stops receiving updates.

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
4. **Push issued?** `.github/workflows/ci.yml` builds `geekom` and `hplaptop`
   from GitHub, and `hplaptop` updates itself unattended from `verified`
   (`nrb` with `--refresh`) — a branch CI fast-forwards only after the build
   goes green, so a commit that fails cannot reach that machine. Still fix or
   revert a failing commit promptly: while `main` is red, `verified` stops
   advancing and the laptop silently stops receiving updates. The full
   branch-to-merge cycle is documented in "Release cycle" above.
