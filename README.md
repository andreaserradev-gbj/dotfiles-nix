# dotfiles-nix

Personal NixOS configuration for a UTM (Apple Silicon) development VM. One
command rebuilds both the system and my `$HOME` from this repository:

```sh
sudo nixos-rebuild switch --flake .#nixos
```

## The model

macOS is the host and stays imperative (always-latest apps, browser, mail).
The dev environment is a NixOS VM in UTM, and *that* is what this repo makes
reproducible. NixOS is not the daily driver — it's the part I want to be able
to rebuild from scratch and get back byte-for-byte.

Everything lives in a single flake with two layers folded together:

- **System layer** — `nixos/configuration.nix` + `nixos/hardware-configuration.nix`
- **Home layer** — Home Manager, wired in as a NixOS module (not a standalone
  `home-manager switch`), so one `nixos-rebuild` builds both.

## Layout

```
flake.nix            nixosConfigurations.nixos (aarch64), HM as a module
home.nix             Home Manager entrypoint — imports modules/
modules/*.nix        one module per tool (zsh, git, neovim, …) — 100% Nix
config/<tool>/…      verbatim assets referenced by the modules (nvim tree,
                     bat theme, fastfetch, zellij) — 100% non-Nix
nixos/               the system layer
```

## Bootstrapping a fresh VM

The goal: a brand-new UTM VM ends up as an exact copy of this environment with
one rebuild. There are two ways in — a full manual install, or cloning a saved
UTM template that already has the base install done.

### Prerequisites

- UTM on Apple Silicon (Virtualize, **not** Emulate — native aarch64).
- The **NixOS 26.05 aarch64 minimal** ISO. Verify its SHA256 before booting it.
- VM settings: ARM64, ~8 GB RAM / 4 cores / ~64 GB disk, **UEFI boot enabled**,
  Shared Network.

### 1. Base install (partition with stable labels)

Boot the ISO to the root shell and confirm networking (`ping nixos.org`).
Partition the disk (`/dev/vda` under UTM's virtio) as GPT: a ~512 MB FAT32 ESP
and an ext4 root. **Label them — the repo mounts by label, not UUID:**

```sh
mkfs.fat -F32 -n BOOT /dev/vda1     # ESP  -> label BOOT
mkfs.ext4  -L nixos   /dev/vda2     # root -> label nixos
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot && mount /dev/disk/by-label/BOOT /mnt/boot
```

> **Why labels?** UUIDs are regenerated on every fresh install. This repo's
> `nixos/hardware-configuration.nix` mounts `/` and `/boot` by the labels
> `nixos` and `BOOT`, so it is install-independent — set the labels here and
> the committed hardware config just works.

Generate a minimal config and make it bootable enough to install:

```sh
nixos-generate-config --root /mnt
```

Edit `/mnt/etc/nixos/configuration.nix` just enough to boot and get back in:

- `boot.loader.efi.canTouchEfiVariables = false;` — **the aarch64/UTM EFI fix.**
  UTM's firmware can't take NVRAM boot-entry writes; systemd-boot uses its
  fallback path instead. Without this the install boots to a dead firmware menu.
- enable flakes, and add your user with an SSH key (or keep the console password)
  so you can reach the machine to clone.

Then install and reboot:

```sh
nixos-install        # set the root password when prompted
reboot               # detach the ISO first
```

This base config is throwaway — the next step replaces it with the repo.

### 2. Clone the repo

Git isn't in the minimal system yet, so pull it in on demand:

```sh
nix-shell -p git
git clone https://github.com/<you>/dotfiles-nix ~/dotfiles-nix
cd ~/dotfiles-nix
```

The clone is over public HTTPS — no GitHub auth needed to *read* the repo.

### 3. One rebuild for the whole environment

```sh
sudo nixos-rebuild switch --flake .#nixos \
  --extra-experimental-features 'nix-command flakes'
```

The `--extra-experimental-features` flag is only needed for this very first
switch, before the flake's own `nix.settings` take effect. After it lands, the
repo enables flakes permanently and the daily command is just:

```sh
sudo nixos-rebuild switch --flake .#nixos
```

This builds *both* layers — system and `$HOME` — from git alone. No separate
`home-manager switch`.

> If the fresh VM's disk layout differs from the committed template, re-run
> `nixos-generate-config`, re-apply the two by-label mount edits, and commit
> the result.

### 4. Open a fresh login shell

The switch relocates user binaries (Home Manager `useUserPackages` moves them
to `/etc/profiles/per-user/andrea/bin`), so the shell you ran the rebuild in
now has stale `PATH` entries — you'll see `no such file … /.nix-profile/bin/…`.
Log out and back in (or `ssh` in fresh). That's expected, not a failure.

At this point the VM is an exact copy of the environment.

### Shortcut: save a UTM template

Instead of repeating the manual install, snapshot a base VM once it's installed
with the labels set and git available. Cloning that template drops you straight
at step 2.

## Daily workflow

Rebuild aliases (defined in `modules/shell.nix`):

| alias | command |
|-------|---------|
| `nrs` / `nrt` / `nrb` | `nixos-rebuild switch` / `test` / `boot` (`--flake .#nixos`) |
| `nfu` / `nfc` | `nix flake update` / `nix flake check` |
| `ngl` / `ngc` | list / collect-garbage generations |
| `nixcfg` | cd to this repo |

**Always `git add` before a `--flake` command.** Flakes only see git-tracked
files, so an untracked new module or asset is invisible to the build — the
error is a confusing "file not found," not "you forgot to stage."

## Gotchas

- **`git add` before `--flake`.** See above — the single most common footgun.
- **`/etc/nixos/*` is vestigial once you're on `--flake`.** A plain
  `nixos-rebuild` (no `--flake`) reads `/etc/nixos/`, but every alias here
  passes `--flake`, so this repo is authoritative. After the first successful
  flake switch you can delete the stale files to enforce a single source of
  truth (see below).
- **Stale running shell after a switch.** Any rebuild that relocates binaries
  leaves the *current* shell pointing at old paths — open a new login shell.
- **Neovim bytecode cache goes stale across rebuilds.** `vim.loader` keys its
  luac cache on path + mtime/size, and Nix pins mtime to 1970 with identical
  sizes on same-length edits, so it can serve stale bytecode. A Home Manager
  activation hook clears `~/.cache/nvim/luac` on every switch; the manual
  escape hatch is the same `rm -rf`.
- **Never force-stop the VM from the macOS host.** There's no reliable ACPI
  shutdown for NixOS-in-UTM-aarch64 — `poweroff` from *inside* the guest, or you
  risk filesystem corruption.

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

## Local console (cage + foot)

The UTM window boots straight into a full-screen [foot](https://codeberg.org/dnkl/foot)
terminal — autologin, no display manager — via [cage](https://github.com/cage-kiosk/cage),
a single-app kiosk Wayland compositor. This is a *local* console for when SSH or
networking is down (or during a bad rebuild), **not** a second workspace: the real
dev loop stays SSH-from-the-Mac (see below). Everything is software-rendered — the
VM has no usable GPU.

Two layers, one rebuild:

- **System** (`nixos/configuration.nix`) — `services.cage` (compositor + autologin),
  `services.spice-vdagentd`, and the `video=` display mode.
- **Home** (`modules/foot.nix`, `modules/fonts.nix`, `modules/starship.nix`) — the
  terminal, its fonts, and the prompt.

### Why these pieces

- **cage, not a desktop.** cage shows exactly one full-screen program and *is* the
  login: its systemd unit (`cage-tty1`) conflicts with `getty@tty1` and autologins
  through a PAM null-password session. No greetd, no display manager.
- **foot, not kitty/alacritty.** foot rasterizes glyphs purely on the CPU — no
  OpenGL/EGL — so it's the one terminal that works on a GPU-less guest. GL-based
  terminals may not even start under software rendering.
- **`WLR_RENDERER = "pixman"` (mandatory).** Forces wlroots' pure-CPU renderer.
  `WLR_RENDERER_ALLOW_SOFTWARE=1` (GLES2-on-llvmpipe) is *not* enough here — EGL
  can't initialize on this guest; pixman bypasses GL entirely. Paired with
  `WLR_NO_HARDWARE_CURSORS=1`, which fixes the cursor rendering at the wrong offset.
- **The Nerd Font is load-bearing.** foot rasterizes glyphs via fontconfig (the
  kernel tty can't), so a correct monospace font is the whole point of a local
  terminal. A small `DejaVu Sans` fallback covers the few Unicode glyphs
  JetBrainsMono Nerd Font lacks (e.g. `⇡` in the git prompt), and the starship
  read-only symbol is set to a Nerd Font lock — so no color-emoji font is needed.
- **`WorkingDirectory = $HOME`.** cage's unit otherwise defaults to `/`, so the
  console would open in the root filesystem. Set on the `cage-tty1` service.

### Fallback

`Ctrl+Alt+F2` reaches a bare kernel tty at all times (cage keeps VT-switching via
its `-s` flag); `Ctrl+Alt+F1` returns to foot. The tty is the true escape hatch, so
cage never has to be bulletproof. SSH is independent of the console entirely — a
broken compositor cannot lock you out: `ssh` in and roll back a generation.

### Development stays on the Mac

The GUI-in-VM is *only* the terminal. Editing, the browser, and the dev loop stay
on the Mac over SSH. To reach a dev server running inside the VM:

```sh
ssh -L 5173:localhost:5173 nixos     # forward the VM port to the Mac
```

or bind the server to `0.0.0.0`, open the firewall port, and hit the VM's IP.

### Known limitations

- **Clipboard is not wired.** `spice-vdagentd` runs, but the session-side
  `spice-vdagent` client that would sync the clipboard is never started (a bare
  cage kiosk has nothing to autostart it). This is intentional for an insurance
  console — use SSH for anything that needs the Mac clipboard. To enable it, have
  cage launch a small wrapper that starts `spice-vdagent` before `exec`-ing foot.
- **Resolution is capped by UTM, not the guest.** `boot.kernelParams` pins the
  virtio-gpu output to `video=Virtual-1:1920x1080` (its default preferred mode is a
  low `1280x800`), but effective sharpness is ultimately bounded by UTM's own
  display scaling — on some setups it looks unchanged. Pick another mode from
  `/sys/class/drm/card0-Virtual-1/modes` and/or raise foot's font `size=`; cage has
  no output-scale knob.
