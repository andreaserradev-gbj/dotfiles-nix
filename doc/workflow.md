# Daily workflow

Rebuild aliases (defined in `modules/home/shell.nix`). They are fronted by
[`nh`](https://github.com/nix-community/nh), a nicer `nixos-rebuild`/GC
front-end. `NH_FLAKE` points at this repo, so **none of them need a path or a
host argument** — the same alias is correct on every machine. `hplaptop` is the
exception: with no checkout and no `nh`, her `nrb` and `ngca` come from
`modules/home/maintenance.nix` instead (see [doc/bare-metal-hplaptop.md](bare-metal-hplaptop.md)).

| alias                 | command                | what it actually does                                             |
| --------------------- | ---------------------- | ----------------------------------------------------------------- |
| `nrp`                 | `nh os build`          | build + diff vs current. **No activation, no generation.**         |
| `nrs`                 | `nh os switch --ask`   | build, show diff, ask, then activate **and** set the boot default  |
| `nrt`                 | `nh os test`           | activate now, don't touch the bootloader — a reboot reverts it     |
| `nrb`                 | `nh os boot`           | stage for next boot, don't activate now                            |
| `nfu`                 | `nix flake update`     | bump every input — rewrites `flake.lock`                           |
| `nfud`                | shell function         | dry run of `nfu`: diff the would-be lock update, write nothing     |
| `nfb`                 | `scripts/nfb.sh`       | bump omp/herdr to upstream's latest release; re-locks omp's flake input only |
| `nfc`                 | `nix flake check`      | validate the flake without building a system                       |
| `nfi` / `nfp`         | `nix flake init -t …`  | drop the devshell / python-devshell template into the current project |
| `ngl` / `ngd` / `ngc` | shell functions        | list / diff / interactively delete generations                     |
| `ngca`                | `nh clean all` + prune | bulk GC keeping the newest, then prune the boot menu               |
| `nixcfg`              | `cd ~/dotfiles-nix`    | jump to this repo                                                  |

**Always `git add` before a `--flake` command.** Flakes only see git-tracked
files, so an untracked new module or asset is invisible to the build. Nix names
it — `Path 'X' … is not tracked by Git`, followed by the `git add` that fixes it
— but only after you have already started the build.
`scripts/check-hosts.sh` warns about untracked files _before_ it prints any
result, precisely because a green result on a stale tree is worse than a red one.

## Which rebuild command, and from where

`nrs` runs in two phases: `switch-to-configuration test` first, then setting
the system profile and `switch-to-configuration boot`. That order is a feature —
a config that cannot activate never becomes the boot default.

The hazard is that phase 1 can restart the display stack, and so tear down the
session `nrs` is running in. It then dies between the two phases, leaving the
activation applied with **no new generation, no bootloader entry and no error
text**.

| situation                        | use                            | why                                                                   |
| -------------------------------- | ------------------------------ | --------------------------------------------------------------------- |
| normal case, SSH available       | `nrp`, then `nrs` **over SSH** | the SSH session is its own scope, so a display restart cannot reap it  |
| at the machine's console, no SSH | `nrp`, then `nrb`, then reboot | `nrb` never runs phase 1, so there is nothing to self-destruct against |
| kernel moved                     | reboot regardless              | `switch` cannot load a new kernel                                      |

> **Never run `nrs` from a machine's own graphical console.** True on every host,
> and it matters more on `geekom`, where recovery costs a physical trip.

> **The loopback exception.** On hosts with the `loopbackRebuild` seam enabled
> (`modules/nixos/loopback-rebuild.nix` — geekom today), `nrs` and `nrt` are
> shell aliases carrying `--target-host andrea@localhost --hostname <this host>`
> (built in `modules/home/shell.nix`), so the activation runs through SSH to
> `localhost`. sshd's session scope is outside the display stack, so the
> graphical-console hazard does not apply to them: they are safe from any
> terminal on the machine. The seam also authorizes the machine's own key and
> pins its host key for `localhost`, so it works on a fresh checkout with no
> manual steps. If sshd is ever broken, fall back to `nh os switch --ask`
> directly — what `nrs` is on a host without the seam — or the `nrb` + reboot
> row above.

> **Diagnosing a switch that appears to have done nothing:** check
> `ls /nix/var/nix/profiles/ | grep system-` for a new generation. No new
> generation means phase 2 never ran. **Do not use a reboot as the test** —
> rebooting after a phase-1-only activation silently reverts it, which is
> indistinguishable from the switch never having happened.

> **What phase 1 validates, and what it does not.** The `test` activation catches
> broken services and activation scripts. It does **not** validate booting: a
> config can activate perfectly and still fail on a bad
> `boot.initrd.availableKernelModules`. Only a reboot tests the boot path. A
> green `nrs` is not "it will boot".

> **`ngca` on a dev host keeps exactly one generation** (`nh clean all`, whose
> `--keep` defaults to 1; hplaptop's is the 14-day variant — see
> [doc/bare-metal-hplaptop.md](bare-metal-hplaptop.md)). A freshly installed host
> has only `system-1-link`, so running it there leaves nothing to roll back to —
> and on bare metal the boot menu is the only recovery path. Wait until several
> generations exist and a reboot has confirmed the current one is healthy.
> `configurationLimit` bounds bootloader _entries_, not generations; they are
> different numbers.

## Checking every host still builds

```sh
./scripts/check-hosts.sh
```

It evaluates **every** host and prints its system `drvPath`. It builds nothing
and touches no system, and because Nix evaluation is architecture-independent
it checks x86_64 `geekom` from the aarch64 VM and vice versa — verified in both
directions, giving byte-identical results.

> **`nix flake check` will not do this for you.** It does not evaluate
> `nixosConfigurations` at all, so a typo in whichever host you are *not*
> sitting on stays invisible until the day you try to build it. For a machine
> in another room that is the worst possible day to find out.

Use the printed `drvPath` as a before/after reference around any change:

- A host you did **not** mean to touch must not move.
- A host that moves for a reason you cannot name has not been understood.

That is the check that makes editing `modules/` safe. Touching a shared module
should move every host's hash; touching `hosts/geekom/` should move exactly one.

## CI

[.github/workflows/ci.yml](../.github/workflows/ci.yml) runs the same gate on
GitHub for every push to `main` and every PR, in four stages:

1. **evaluate** — on an x86_64 runner: `nix fmt -- --ci` (format check, fails
   on an unformatted file), `statix check .`, `deadnix --fail`, and
   `./scripts/check-hosts.sh`. The eval step is the same gate as above, on
   purpose: evaluation is arch-independent, so the aarch64 VM is covered too.
   In a fresh CI checkout every file is git-tracked, so the format check covers
   everything; a local bare `nix fmt` on a dirty tree skips untracked files
   (treefmt's git walk) and then only the pre-commit hook covers the staged set.

   **The two linters run here and nowhere else.** The pre-commit hook runs
   `nixfmt` alone, so CI is the only place `statix` or `deadnix` can fail a
   change — locally they are devShell tools you have to invoke yourself.
   `deadnix` needs `--fail` to be a gate at all: without it it reports findings
   and still exits 0. Both come from the flake's devShell, so CI and
   `nix develop` run the same pinned versions, and `statix.toml`'s
   disabled-lint list applies identically in both.
2. **build** — a matrix that fully builds host toplevels from
   `cache.nixos.org` substitution (the stable-26.05 pin makes this a
   ~minutes-long download, not a compile). It runs only after `evaluate`
   passes — an eval-breaking typo fails in seconds instead of wasting two
   build runners.

   **The matrix only contains hosts whose `drvPath` actually moved.**
   `scripts/changed-hosts.sh` compares each candidate host against the same
   host on `verified` — the last commit whose build passed — and emits the
   movers as a JSON array. An identical `drvPath` is not a guess that the host
   is fine: it is the *same derivation*, and that derivation already built
   green, so rebuilding it proves nothing. A doc- or CI-only change moves no
   host and skips the matrix entirely; a `flake.lock` bump moves every host and
   skips nothing. Measured: geekom alone is ~6 minutes of closure download.

   The baseline is `verified`, not `main`, deliberately. `main` can hold a
   commit whose build is still running or has failed; comparing against it
   could skip a build on the strength of one that never succeeded.

   The candidate set (`geekom hplaptop`) is named in `ci.yml`, not in the
   script, so the "what does CI build" policy stays next to the comment that
   explains why the aarch64 VM is excluded.
3. **gate** — the single required status check. It always runs and just
   aggregates the jobs above, accepting a `build` result of either `success`
   or `skipped`.

   This job exists because of how branch protection treats skips. Requiring
   `build (geekom)` and `build (hplaptop)` directly would deadlock the first
   time a build is skipped: a required check that never reports leaves the PR
   *waiting for status*, not passing. Protection therefore requires `evaluate`
   and `gate` — never a matrix job, whose very name depends on the matrix
   being non-empty.
4. **advance-verified** — on a green push to `main` only, fast-forwards the
   `verified` branch to that commit. `needs: gate` is the whole point:
   `verified` can only ever name a commit whose x86_64 hosts were either built
   here or proven byte-identical to a commit that was.
   The push is non-forced, so a diverged `verified` fails the job loudly
   instead of being rewritten.

   Its `if:` starts with `always()`, which is load-bearing rather than
   decorative. A skipped job propagates skip *transitively* through the `needs`
   graph: when `build` skips, `gate` rescues itself with `always()` and passes,
   but anything downstream of `gate` still inherits that skip unless it opts
   out of the default `success()` semantics too. Without it, every doc- or
   CI-only commit silently fails to advance `verified` — which happened once,
   on `005b6107`.

   hplaptop's `nrb` pulls this branch (`modules/home/maintenance.nix`), which
   is what makes the job load-bearing rather than bookkeeping: the gate ends at
   a machine.

Because the gate is enforced, a PR cannot be merged until it reports green,
and waiting on it by hand is wasted time. Open PRs with auto-merge and walk
away — GitHub merges the moment the required checks pass:

```sh
gh pr merge <n> --auto --squash
```

Third-party actions are pinned to full commit SHAs with the tag in a trailing
comment. There is no dependabot here, so bumping is manual: resolve the new SHA
with `git ls-remote --tags <repo>` and replace both the pin and the comment.

Two things this file cannot assert, because they live in GitHub's UI:
the repo's Actions **workflow permissions** must stay read-only (the workflow
declares `permissions: contents: read`, and only `advance-verified` re-grants
`contents: write` for itself), and **branch protection** on `main`. Without the
latter CI is advisory: red runs still merge, `advance-verified` simply does not
fire, and `verified` quietly stops advancing rather than loudly breaking.

The point is the **`nrb` from GitHub path**: `bare-metal-hplaptop.md` has an
unattended host (`nrb` pulls from `github:` with `--refresh`), so whatever that
alias fetches gets installed on that machine without anyone watching. It
fetches `verified`, and `verified` moves only when `advance-verified`
fast-forwards it behind a green `gate`. A commit that does not build therefore
cannot reach the laptop at all: a red `main` leaves `verified` where it was, and
the machine keeps running the last commit that built.

The AGENTS.md rule that a failing commit is fixed or reverted promptly still
matters, though for a different reason than it was written for: while `main` is
red, `verified` stops advancing and the laptop quietly stops receiving updates.

The aarch64 VM is **not** in the build matrix: it is dormant (README's host
list) and only `evaluate` covers it — `ci.yml` carries the reason next to the
candidate list. If the build
jobs ever start *compiling* instead of substituting, look for drift (an input
off the stable channel), not for disk space — the 60-minute job timeout
bounds what that drift scenario can burn.

## Upgrading to a new NixOS release

The release is pinned in exactly **two URLs** in `flake.nix`:

```nix
nixpkgs.url = "github:NixOs/nixpkgs/nixos-<release>";
home-manager.url = "github:nix-community/home-manager/release-<release>";
```

Nothing else in the repo names the release in a functional way, except the two
dev-shell templates (`templates/devshell/flake.nix`,
`templates/python-devshell/flake.nix`), which pin the same branch so a project
shell reuses store paths the system already has — bump their `nixos-<release>`
refs too. The `home-manager` line must track the `nixpkgs` line because HM
release branches are cut per NixOS release (and wired with `follows`, so it
inherits the same nixpkgs evaluation).

To move to a new release (e.g. 26.05 → 26.11):

1. Edit the two refs in `flake.nix` (and the two in `templates/*/flake.nix`).
2. `nix flake update nixpkgs home-manager` — re-resolves the lock to the new
   branch (`nfu` alone re-resolves *within* the pinned branch only).
3. `nrp`, review the diff, then activate per the table above.
4. Reboot — a release jump moves the kernel and the display stack, so this is
   the "kernel moved" row, not the "normal case" row.

> **Never bump `stateVersion`.** `system.stateVersion` and `home.stateVersion`
> are one-way migration-semantics flags, not "what release am I on" indicators.
> They stay at the release the machine was *installed* with, forever — even
> after upgrading. The vm's `"Did you read the comment?"` marker exists to
> guard exactly this.

> **Pre-flight for the next jump (26.05 → 26.11):** verify `ollama-vulkan`
> still exists as an attribute in the new nixpkgs and that the
> `OLLAMA_IGPU_ENABLE` reasoning in `hosts/geekom/default.nix` still applies —
> the vulkan backend is the fragile spot on the geekom box (see the
> ROCm-regression comment there). A missing attribute fails at eval time, so
> `nrp` catches it before anything is activated.

Between releases, version bumps for fast-moving CLI tools (opencode, zellij)
land on `nixos-unstable` only — they are not backported to the stable
branch, so seeing no version movement on `nfu` is the normal condition, not a
broken update. Two tools are the exception, both pinned from
`nixpkgs-unstable` via the escape hatch below: `ollama` since 2026-09-11 and
`opencode` since 2026-09-22. For both, `nfu` (or a targeted
`nix flake update nixpkgs-unstable`) DOES move them.

### Need a newer version before the next release?

The escape hatch is a second nixpkgs input tracking `nixos-unstable`,
consumed for a **small, explicit selection of tools**:

```nix
inputs.nixpkgs-unstable.url = "github:NixOs/nixpkgs/nixos-unstable";
```

The input exists in [flake.nix](../flake.nix) today, and the binding is
**passed to every host**: `specialArgs` on each `nixosConfigurations` entry
carries `unstablePkgs = nixpkgs-unstable.legacyPackages.<system>` because a
shared module consumes it — `modules/nixos/dev.nix` takes it for opencode.
What stays gated is the *forcing*: the second tree is evaluated lazily, on
first reference, and only these sites reference it — `ollama-vulkan` in
[hosts/geekom/default.nix](../hosts/geekom/default.nix) and `unstablePkgs.opencode`
inside dev.nix's `mkIf cfg.enable`. hplaptop receives the binding and her
closure is byte-identical (`check-hosts.sh` is the proof: her drvPath has never
moved across this refactor). So the rule for new code is: reference
`unstablePkgs` from a host file, or from a shared module **behind the dev
gate** — never from shared code every host evaluates unconditionally.

Adopted for two packages so far:

- `ollama-vulkan` on geekom
  ([hosts/geekom/default.nix](../hosts/geekom/default.nix), 2026-09-11): 0.32.15+
  halves TTFT, 0.33.0 fixes agent prefill-restore on recurrent-layer models,
  0.33.3 honors GGUF default parameters — measured gains, not cosmetics, with the
  GPU-path risk discharged by the on-box verification after every rebuild
  (MTP flag, 100% GPU, decode rate; see
  [doc/local-llm.md](local-llm.md)). The older caution against pulling ollama
  from unstable mid-cycle was written without measurements and is superseded by
  that doc.
- `opencode` on geekom and the VM (2026-09-22), through
  [modules/nixos/dev.nix](../modules/nixos/dev.nix) (`unstablePkgs.opencode` in
  its `environment.systemPackages`, inside the dev gate): 26.05 carries
  1.15.10 while unstable carries 1.18.x, three minor series of agent fixes the
  stable branch will not have before the next release. Adopted with no on-box
  gate because the tool is a userland CLI with no daemon, no GPU path and no
  vendored C/C++ backend — the reason this row was named a fit long before it
  was taken. Cost paid: geekom's closure grows by ~104 MiB (`nvd`-verified) and
  the unstable tree's `bash`/`ripgrep`/`pcre2` come along for opencode's
  wrapper, so a stable-tree `nfu` no longer implies "nothing in the closure
  compiles" for these two hosts. Both opencode outputs substitute from
  cache.nixos.org on x86_64 and aarch64, so neither CI nor the VM compiles it.

For any NEW tool: the trade-off is a second nixpkgs evaluation (lazy, but a
daily-moving lock entry) versus a version the stable branch will not carry
until the next release. A remaining candidate that would fit: `zellij`
(userland, low blast radius — 0.45.1 is identical on both trees today, which is
why it has not been adopted). Anything whose runtime behavior moves with its
vendored C/C++ backend (like ollama did) must go through the geekom
verification gate after each re-pin — that gate is the discharge, not a reason
to avoid the bump.

## Cleaning up `/etc/nixos`

Once the first `--flake` switch succeeds, `/etc/nixos/configuration.nix` and
`/etc/nixos/hardware-configuration.nix` are no longer read (every rebuild here
goes through `--flake`). To keep a single source of truth, either remove them:

```sh
sudo rm /etc/nixos/configuration.nix /etc/nixos/hardware-configuration.nix
```

or stub `configuration.nix` with a comment pointing at this repo. A fresh
install regenerates `hardware-configuration.nix` regardless, so nothing here is
load-bearing after the flake takes over.

---

- Install walkthroughs: [doc/install-vm.md](install-vm.md),
  [doc/bare-metal-geekom.md](bare-metal-geekom.md),
  [doc/bare-metal-hplaptop.md](bare-metal-hplaptop.md)
- Per-project dev shells: [doc/dev-environments.md](dev-environments.md)
- Common failure modes: [doc/troubleshooting.md](troubleshooting.md)
