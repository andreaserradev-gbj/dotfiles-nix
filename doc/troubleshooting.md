# Gotchas

- **`git add` before `--flake`.** Flakes only see git-tracked files — the single
  most common footgun. See [doc/workflow.md](workflow.md) for the alias table
  and the `check-hosts.sh` untracked-file warning.
- **`/etc/nixos/*` is vestigial once you're on `--flake`.** A plain
  `nixos-rebuild` (no `--flake`) reads `/etc/nixos/`, but every alias here
  passes `--flake`, so this repo is authoritative. After the first successful
  flake switch you can delete the stale files to enforce a single source of
  truth (see [doc/workflow.md](workflow.md), "Cleaning up `/etc/nixos`").
- **Stale running shell after a switch.** Any rebuild that relocates binaries
  leaves the _current_ shell pointing at old paths — open a new login shell.
- **Neovim bytecode cache goes stale across rebuilds.** `vim.loader` keys its
  luac cache on path + mtime/size, and Nix pins mtime to 1970 with identical
  sizes on same-length edits, so it can serve stale bytecode. A Home Manager
  activation hook clears `~/.cache/nvim/luac` on every switch; the manual
  escape hatch is the same `rm -rf`.
- **Never force-stop the VM from the macOS host.** There's no reliable ACPI
  shutdown for NixOS-in-UTM-aarch64 — `poweroff` from _inside_ the guest, or you
  risk filesystem corruption.
- **`nix flake check` does not check `nixosConfigurations`.** Use
  `./scripts/check-hosts.sh` instead — see [doc/workflow.md](workflow.md).

---

- Daily workflow and rebuild aliases: [doc/workflow.md](workflow.md)
- Local console fallback when SSH is down: [doc/vm-console.md](vm-console.md)
