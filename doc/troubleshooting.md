# Gotchas

- **`git add` before `--flake`.** Flakes see git-tracked files only — the single
  most common footgun; see [doc/workflow.md](workflow.md) and `check-hosts.sh`'s
  untracked-file warning.
- **`/etc/nixos/*` is vestigial once you're on `--flake`.** Every alias here
  passes `--flake`, so this repo is authoritative and the stale files can go —
  see [doc/workflow.md](workflow.md), "Cleaning up `/etc/nixos`".
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
  `./scripts/check-hosts.sh` ([doc/workflow.md](workflow.md)).
- **geekom: the Razer Basilisk V3 intermittently fails USB enumeration at
  cold boot, on ANY port** — the mouse's own controller misses the kernel's ~4 s
  retry window at power-on, and the kernel never retries, so it stays dead until
  a replug. `hosts/geekom/usb-mouse-recovery.nix` emulates that replug at boot:
  after an 8 s settle it bounces the mouse's xHCI PCI function (`0000:c8:00.0`,
  buses 3+4 only; BT radio and Corne are on separate functions) when `1532:0099`
  is absent, and is a no-op on clean boots. Rear ports are still preferred for
  latency/SS hygiene, but they are not a fix. Check:
  `journalctl -u usb-mouse-recovery -b`.
- **Thunderbolt peripheral: the display works but its USB features never
  appear = the device was never authorized.** A TBT monitor or dock tunnels
  DisplayPort WITHOUT authentication, so video always comes up; the
  PCIe/USB3 tunnels that carry its internal hub (speakers, camera, dock
  ports) stay down until the device is authorized. Security level is `user`
  on both geekom domains (`boltctl domains`), and
  `iommu_dma_protection = 0` on both, so boltd's free IOMMU auto-enroll path
  is dead there — every new device needs one explicit enrollment. Symptoms:
  `boltctl list` shows the device `connected` with no authorization line
  (`stored: no`, sysfs `authorized: 0`), nothing from it in `lsusb`, and
  GNOME logs `thunderbolt: [name] auto enrollment: no (allowed: no)`.
  Fix, ONCE per device per host: `boltctl enroll --policy auto <uuid>`
  (uuid from `boltctl list`) — stored in `/var/lib/boltd`, survives
  rebuilds and reboots, auto-authorized on every future connect; GNOME
  Settings → Thunderbolt is the GUI path to the same. NOT affected: plain
  DP/HDMI and DP-alt-mode USB-C monitors — no TBT tunneling, so their audio/USB
  failures are a different path (see the Razer entry above for one such
  kernel-side failure).

---

- Daily workflow and rebuild aliases: [doc/workflow.md](workflow.md)
- Local console fallback when SSH is down: [doc/vm-console.md](vm-console.md)
