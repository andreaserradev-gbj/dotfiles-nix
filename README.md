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
user.nix             personal identity — the one file to edit when forking
home.nix             Home Manager entrypoint — imports modules/
modules/*.nix        one module per tool (zsh, git, neovim, …) — 100% Nix
config/<tool>/…      verbatim assets referenced by the modules (nvim tree,
                     bat theme, fastfetch, zellij) — 100% non-Nix
nixos/               the system layer
```

## Bootstrapping a fresh VM

The goal: a brand-new UTM VM ends up as an exact copy of this environment. The
supported path is a **one-command scripted install** (`bootstrap.sh`); the manual
steps are kept further down as a fallback/reference.

> **Forking?** Everything personal lives in one file, [`user.nix`](user.nix):
> `username`, `fullName`, `email`, `timeZone`, and `sshKey`. Edit it in your fork
> and commit *before* installing — `bootstrap.sh` pulls the config from git, so the
> VM is built with whatever identity your pushed `user.nix` carries. Point the
> bootstrap/install URLs below at your fork.

### 1. Create the UTM VM

- **UTM on Apple Silicon**, **Virtualize** (native aarch64) — *not* Emulate.
- **NixOS 26.05 aarch64 minimal** ISO — verify its SHA256, then attach it as the
  boot image (Operating System → Other → Boot ISO Image).
- Memory / CPU: ~8 GB RAM, 4 cores.
- Storage: ~64 GB disk.
- **UEFI boot enabled** (the aarch64 systemd-boot install depends on it).
- **Shared Network** — gives the guest a host-visible NAT IP (`192.168.64.x`), so
  you SSH to it by IP with no port-forward.

Boot the ISO to the installer's root shell and confirm networking (`ping nixos.org`).

### 2. One-command install

From the booted ISO's root shell:

```sh
curl -fsSL https://raw.githubusercontent.com/andreaserradev-gbj/dotfiles-nix/main/bootstrap.sh | sudo bash
```

`bootstrap.sh` (at the repo root) runs the whole install non-interactively:

1. **disko** partitions, formats, and mounts `/dev/vda` from `nixos/disk-config.nix`
   — GPT with a labelled `BOOT` ESP and a labelled `nixos` ext4 root. **This wipes
   the disk** (`--yes-wipe-all-disks`).
2. `nixos-install --flake …#nixos --no-root-passwd` builds *both* layers — system
   and `$HOME` — straight from the flake.

There's no `nixos-generate-config` and no throwaway config: the committed
`hardware-configuration.nix` mounts by those two labels and `configuration.nix`
already carries the EFI fix and your SSH key, so a fresh install collapses to disko
+ one `nixos-install`.

> **Why `-fsSL`, not `-sL`?** `-f` makes curl fail loudly on a bad URL instead of
> silently piping a 404 HTML page into `sudo bash` (which then surfaces as the
> baffling `404:: command not found`). The install is also non-interactive by
> necessity — a piped installer has no TTY, so the script passes
> `--yes-wipe-all-disks` (disko's wipe confirm) and `--no-root-passwd`
> (nixos-install's root-password prompt); either prompt would otherwise abort it.

When it finishes:

1. In UTM, detach the ISO (Drive → eject).
2. `reboot`.

The VM boots straight into the cage+foot console (autologin). Log in from the Mac
over SSH with your key — next.

### 3. SSH from the Mac

Access is **key-only**: `configuration.nix` sets
`services.openssh.settings.PasswordAuthentication = false`, so the key in `user.nix`
is the *only* way in over the network — there is no password fallback.

1. **Generate a key** on the Mac (skip if you already have one):

   ```sh
   ssh-keygen -t ed25519 -C "you@example.com"
   ```

2. **Put its public half in `user.nix`** as `sshKey = "ssh-ed25519 …";` and commit.
   `configuration.nix` installs it into the VM's `authorizedKeys` at build time, so
   it must be in the repo *before* the install in step 2.

3. **Find the VM's IP** from the local console — it's a DHCP lease, so it can change
   across reboots:

   ```sh
   ip -4 addr show enp0s1        # the 192.168.64.x on the virtio NIC
   ```

4. **Add a `Host` block** to the Mac's `~/.ssh/config`:

   ```
   Host nixos
     HostName 192.168.64.12          # the IP from step 3
     User andrea
     IdentityFile ~/.ssh/id_ed25519
     IdentitiesOnly yes
     # Throwaway local VM: its host key changes across live-ISO reboots and after
     # install, so skip the known_hosts nag. Safe ONLY for a VM you control on a
     # private vmnet subnet — never copy these two lines to a real host.
     StrictHostKeyChecking no
     UserKnownHostsFile /dev/null
   ```

   Then just `ssh nixos`.

> **Key-only lockout caveat.** With password auth off, a missing or wrong key means
> no SSH access at all — recover from the local cage+foot console (autologin), fix
> `user.nix`, and rebuild. Get the key right in `user.nix` before installing.

### Manual install (fallback / reference)

If you'd rather drive the install by hand — or `bootstrap.sh` won't run — do what
the script does, by hand. Boot the ISO to the root shell, confirm networking, then:

**Partition `/dev/vda` (UTM's virtio disk) as GPT with stable labels.** The repo
mounts by label, not UUID:

```sh
mkfs.fat -F32 -n BOOT /dev/vda1     # ESP  -> label BOOT
mkfs.ext4  -L nixos   /dev/vda2     # root -> label nixos
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot && mount /dev/disk/by-label/BOOT /mnt/boot
```

> **Why labels?** UUIDs are regenerated on every fresh install. `nixos/hardware-configuration.nix`
> mounts `/` and `/boot` by the labels `nixos` and `BOOT`, so it is
> install-independent — set the labels here and the committed hardware config just
> works. (`nixos/disk-config.nix` sets these same labels; disko and this manual path
> produce an identical layout.)

**Install straight from the flake** — no `nixos-generate-config`, since the
committed config already carries the by-label mounts, the EFI fix
(`boot.loader.efi.canTouchEfiVariables = false`, the aarch64/UTM fix — UTM's
firmware can't take NVRAM boot-entry writes, so systemd-boot uses its fallback
path), and your SSH key:

```sh
export NIX_CONFIG="experimental-features = nix-command flakes"
nixos-install --flake github:andreaserradev-gbj/dotfiles-nix#nixos
reboot               # detach the ISO first
```

> If a fresh VM's disk layout ever differs from the committed template, re-run
> `nixos-generate-config`, re-apply the two by-label mount edits, and commit.

**Stale running shell after a rebuild.** The daily `nixos-rebuild switch` relocates
user binaries (Home Manager `useUserPackages` moves them to
`/etc/profiles/per-user/andrea/bin`), so the shell you ran it in keeps stale `PATH`
entries — you'll see `no such file … /.nix-profile/bin/…`. Open a fresh login shell
(or `ssh` in again). Expected, not a failure. (A fresh install reboots anyway, so
this only bites on daily switches.)

### Shortcut: save a UTM template

Instead of repeating the install, snapshot a base VM once it's installed. Cloning
that template drops you straight at a working system you can `nixos-rebuild` on.

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
