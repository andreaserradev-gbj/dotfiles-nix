---
name: verify-dotfiles-nix
description: >
  Verify changes in the dotfiles-nix NixOS flake: evaluate every host, run the
  CI lint gates, diff host closures, and build changed toplevels — all without
  activating anything on the running machine.
---

# Verify dotfiles-nix

The "app" is the flake itself: three NixOS hosts (`geekom`, `hplaptop`, `nixos`)
built from one `nixosConfigurations` set. There are no servers, ports, services,
or seed data. Verification = **evaluate → lint → diff → build**. Activation
(`nrs` / `nrt` / `nrb` / any `nh os switch`) is NEVER agent-run: it mutates the
machine and needs the user's explicit go-ahead (see "Activation" below).

## Rules that gate everything

1. **`git add` changed files before any flake command.** Nix evaluates the git
   INDEX, not the working tree; an untracked file is invisible to it. The error
   (`Path 'X' … is not tracked by Git`) only appears after you started — check
   `git status --porcelain` first.
2. **`nix flake check` is not a gate here.** It does not evaluate
   `nixosConfigurations`, so a typo in the host you are not sitting on passes it.
3. **Never touch `system.stateVersion` / `home.stateVersion`** — pinned at
   install time, one-way migration-semantics flags.
4. The agent typically runs ON a build target (e.g. geekom). Eval and build are
   safe there; activation is not.

## 1. Evaluate — the multi-host gate

```bash
./scripts/check-hosts.sh
```

Exit 0 + one `<host> <drvPath>` line per host (~20 s warm):

```
geekom   /nix/store/najailfl0aq1vny4axmmswjj03zfs8yn-nixos-system-geekom-26.05….drv
hplaptop /nix/store/v1zwdfkzpnxkg6bmpxh2axyg0275cgab-nixos-system-hplaptop-26.05….drv
nixos    /nix/store/xb90baxgk4fn1dg14mk6s1inl577r4y2-nixos-system-nixos-26.05….drv
```

- It prints an `!! WARNING: untracked files` block BEFORE any result when the
  tree is dirty in the git-index sense — never reason from a green run that
  showed this warning; `git add` and rerun.
- Record the drvPaths. Around any change, a host you did not mean to touch must
  keep the SAME drvPath; the drvPath is the identity CI compares against the
  `verified` ref.

## 2. Lint — exactly what CI's `evaluate` job runs

```bash
nix fmt -- --ci                 # treefmt + nixfmt, check mode: "0 changed" = pass
nix develop -c statix check .   # antipattern lint
nix develop -c deadnix --fail   # dead code (the --fail is what makes it a gate)
```

First run fetches the formatter (~seconds from cache). `error (ignored): SQLite
database … is busy` lines from the eval cache under concurrent nix calls are
ignorable noise.

## 3. Diff — which hosts moved, and what moved inside them

```bash
./scripts/changed-hosts.sh                              # all hosts vs `verified`
./scripts/changed-hosts.sh <ref> <host…>                # restrict set/ref
```

JSON array on stdout (empty `[]` = nothing moved, nothing to build); per-host
reasoning (`unchanged` / `MOVED was … now …`) on stderr. Unknown host names fail
loudly. The baseline is evaluated at the REF's own commit and lock, not the
local checkout — a lock bump legitimately moves every host.

To explain a moved host at package level, diff the two drvPaths:

```bash
# baseline sha comes from changed-hosts.sh's stderr line: "baseline: <ref> @ <sha>"
old=$(nix eval --raw "github:<owner>/<repo>/<baseline-sha>#nixosConfigurations.<host>.config.system.build.toplevel.drvPath")
new=$(nix eval --raw ".#nixosConfigurations.<host>.config.system.build.toplevel.drvPath")
nix store diff-closures "$old" "$new"    # or: nvd diff "$old" "$new" where nvd exists
```

An empty package diff is a valid explanation (drvPath moved for a non-package
reason); a nonempty diff must be nameable package by package. `hplaptop` has no
`nvd` — use `nix store diff-closures` there.

## 4. Build — the real proof, still non-mutating

```bash
nix build ".#nixosConfigurations.<host>.config.system.build.toplevel" --print-build-logs
```

- Substitutes from `cache.nixos.org`; only hosts whose drvPath MOVED need this.
  An identical drvPath is the same derivation already built green on `verified`
  — rebuilding it proves nothing (CI skips it for the same reason).
- Creates a `result` symlink in cwd — gitignored; remove or leave.

## 5. Activation — never autonomous

| Command | Effect | Agent may run? |
| --- | --- | --- |
| `nrp` (`nh os build`) | build + diff, no activation | yes |
| `nrs` (`nh os switch --ask`) | activate + set boot default | only with explicit user go-ahead |
| `nrt` / `nrb` | activate now / stage for next boot | only with explicit user go-ahead |

Procedure and hazards live in `doc/workflow.md` ("Which rebuild command, and
from where"): run `nrs` over SSH or via the loopback seam, never from a
graphical console on a host without the seam; kernel moved → reboot regardless;
a green switch is not proof the machine boots. Report `nrp`'s diff to the user
and stop — activation is their call.

## Evidence checklist ("verified" means all of these)

1. `check-hosts.sh` green with no untracked warning; unchanged hosts kept their
   drvPath, exactly the intended hosts moved.
2. Lint trio green (`nix fmt -- --ci`, `statix check .`, `deadnix --fail`).
3. `changed-hosts.sh` output matches intent (which hosts MOVED, vs `verified`).
4. Every MOVED host's toplevel built from cache substitution.
5. Closure diff explained: every package delta named, or empty and explained.

## Cleanup

No processes to stop. `result*` symlinks are gitignored. Store paths stay until
the user runs GC (`ngca`). Trial edits revert with
`git restore --staged --worktree` plus one rebuild — nothing else persists.
