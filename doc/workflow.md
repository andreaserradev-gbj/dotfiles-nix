# Daily workflow

Rebuild aliases (defined in `modules/home/shell.nix`). They are fronted by
[`nh`](https://github.com/nix-community/nh), a nicer `nixos-rebuild`/GC
front-end. `NH_FLAKE` points at this repo, so **none of them need a path or a
host argument** — the same alias is correct on every machine.

| alias                 | command                | what it actually does                                             |
| --------------------- | ---------------------- | ----------------------------------------------------------------- |
| `nrp`                 | `nh os build`          | build + diff vs current. **No activation, no generation.**         |
| `nrs`                 | `nh os switch --ask`   | build, show diff, ask, then activate **and** set the boot default  |
| `nrt`                 | `nh os test`           | activate now, don't touch the bootloader — a reboot reverts it     |
| `nrb`                 | `nh os boot`           | stage for next boot, don't activate now                            |
| `nfu`                 | `nix flake update`     | bump every input — rewrites `flake.lock`                           |
| `nfc`                 | `nix flake check`      | validate the flake without building a system                       |
| `nfi`                 | `nix flake init -t …`  | drop the devshell template into the current project                |
| `ngl` / `ngd` / `ngc` | shell functions        | list / diff / interactively delete generations                     |
| `ngca`                | `nh clean all` + prune | bulk GC keeping the newest, then prune the boot menu               |
| `nixcfg`              | `cd ~/dotfiles-nix`    | jump to this repo                                                  |

**Always `git add` before a `--flake` command.** Flakes only see git-tracked
files, so an untracked new module or asset is invisible to the build — the
error is a confusing "path does not exist," not "you forgot to stage."
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

> **`ngca` keeps exactly one generation.** A freshly installed host has only
> `system-1-link`, so running it there leaves nothing to roll back to — and on
> bare metal the boot menu is the only recovery path. Wait until several
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

## Upgrading to a new NixOS release

The release is pinned in exactly **two URLs** in `flake.nix`:

```nix
nixpkgs.url = "github:NixOs/nixpkgs/nixos-<release>";
home-manager.url = "github:nix-community/home-manager/release-<release>";
```

Nothing else in the repo names the release in a functional way. The
`home-manager` line must track the `nixpkgs` line because HM release branches
are cut per NixOS release (and wired with `follows`, so it inherits the same
nixpkgs evaluation).

To move to a new release (e.g. 26.05 → 26.11):

1. Edit the two refs in `flake.nix`.
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

Between releases, version bumps for fast-moving CLI tools (opencode, zellij,
ollama) land on `nixos-unstable` only — they are not backported to the stable
branch, so seeing no version movement on `nfu` is the normal condition, not a
broken update.

### Need a newer version before the next release?

The escape hatch is a second nixpkgs input tracking `nixos-unstable`,
consumed for a **small, explicit selection of tools**:

```nix
inputs.nixpkgs-unstable.url = "github:NixOs/nixpkgs/nixos-unstable";
```

Then reference `pkgs.unstable.<tool>` for just those packages (via an overlay or
`nixpkgs.overlays`), leaving the rest of the system on the stable branch.
Deliberately **not** implemented today — the trade-off (a second nixpkgs
evaluation, an input that moves daily) is only worth it when a specific tool's
newer version is actually needed. Candidates if it ever matters: `zellij` and
`opencode` (userland, low blast radius). **Not** `ollama`: the geekom box uses
the `ollama-vulkan` variant, whose vendored llama.cpp moves with every release
— bumping it mid-cycle risks the GPU inference path for no functional gain.

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
