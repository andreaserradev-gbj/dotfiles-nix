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
- **geekom's four front USB ports are wired through an internal Genesys Logic
  hub** (`05e3:0610`, kernel path `3-1.x`), not straight to the SoC. On cold
  boots the hub-vs-device power-up race intermittently loses enumeration
  (`device descriptor read/64, error -32`, then `unable to enumerate`), and a
  replug is the only fix — observed with a Razer Basilisk V3, 2026-09-08. A
  hotplug always enumerates cleanly, which is why the failure never shows
  after a warm restart. Mice/keyboards belong in a **rear** port (direct root
  port, `3-2` or single-port buses 5/8 — same wiring the Corne uses on bus 7).
  The check is `lsusb -t`: a HID device directly under a `root_hub` line with
  no `Hub` line above it means direct. Nothing in the config can cause or fix
  this — it is board wiring, and the fix is port choice.

---

- Daily workflow and rebuild aliases: [doc/workflow.md](workflow.md)
- Local console fallback when SSH is down: [doc/vm-console.md](vm-console.md)
