# Installing a host — the UTM VM

The goal: a brand-new VM ends up as an exact copy of this environment. The
supported path is a **one-command scripted install** (`bootstrap.sh`), which
takes the host as an argument:

```sh
curl -fsSL https://raw.githubusercontent.com/andreaserradev-gbj/dotfiles-nix/main/bootstrap.sh \
  | sudo bash -s -- <host>            # host is `nixos`, `geekom` or `hplaptop`
```

Boot the NixOS minimal ISO **for the target's own architecture** first —
aarch64 for the VM, x86_64 for both bare-metal hosts.

Real hardware has its own walkthroughs — firmware, boot order, wifi carry-over,
Bluetooth — under [doc/bare-metal-geekom.md](bare-metal-geekom.md) and
[doc/bare-metal-hplaptop.md](bare-metal-hplaptop.md).

> **Forking?** Everything personal lives in one file, [`user.nix`](../user.nix):
> `username`, `fullName`, `email`, `timeZone`, and `sshKey`. Edit it in your fork
> and commit _before_ installing — `bootstrap.sh` pulls the config from git, so the
> machine is built with whatever identity your pushed `user.nix` carries. Point the
> bootstrap/install URLs below at your fork.

## 1. Create the UTM VM

- **UTM on Apple Silicon**, **Virtualize** (native aarch64) — _not_ Emulate.
- **NixOS 26.05 aarch64 minimal** ISO — verify its SHA256, then attach it as the
  boot image (Operating System → Other → Boot ISO Image).
- Memory / CPU: ~8 GB RAM, 4 cores.
- Storage: ~64 GB disk.
- **UEFI boot enabled** (the aarch64 systemd-boot install depends on it).
- **Shared Network** — gives the guest a host-visible NAT IP (`192.168.64.x`), so
  you SSH to it by IP with no port-forward.
- **Console resolution** — QEMU's virtio-gpu advertises `1280x800` as its
  preferred mode and the cage console always follows the host's preferred mode,
  so without this the local console renders at 1280 wide. Add two entries under
  VM Settings → QEMU → Arguments:
  `-global virtio-gpu-pci.xres=1680` and `-global virtio-gpu-pci.yres=1050`.
  Takes effect on the next full VM start (a guest reboot is not enough).

Boot the ISO to the installer's root shell and confirm networking (`ping nixos.org`).

## 2. One-command install

From the booted ISO's root shell:

```sh
curl -fsSL https://raw.githubusercontent.com/andreaserradev-gbj/dotfiles-nix/main/bootstrap.sh \
  | sudo bash -s -- nixos
```

> **`-s --` is load-bearing.** Without it `bash` reads `nixos` as a _script
> filename_, fails to open it, and exits 127 having installed nothing. `-s`
> tells bash to keep taking the script from stdin; `--` ends bash's own option
> parsing so the next word reaches the script as `$1`.

`bootstrap.sh` (at the repo root) runs the install in four announced phases:

1. **Pre-flight.** Fetches `hosts/<host>/disk-config.nix` over HTTPS, reads the
   target device back out of the file it actually fetched, and refuses to go on
   if that path is still a `PLACEHOLDER`. A wrong device costs two seconds here
   instead of surfacing after partitioning, on hardware you are standing in
   front of.
2. **Confirm.** Prints the host, the layout URL and **the disk it is about to
   wipe**, then makes you type the host name back before anything is touched.
3. **disko** partitions, formats and mounts that device from the layout fetched
   in phase 1 — GPT with a labelled `BOOT` ESP and a labelled ext4 root. **This
   wipes the disk** (`--yes-wipe-all-disks`).
4. **`nixos-install --flake github:…#<host> --no-root-passwd`** builds _both_
   layers — system and `$HOME` — straight from the flake.

There's no `nixos-generate-config` and no throwaway config: the committed
`hardware-configuration.nix` mounts by those two labels and
`hosts/<host>/default.nix` already carries your SSH key, so a fresh install
collapses to disko plus one `nixos-install`.

> **The install is interactive, by design.** An unattended disk wipe is the one
> thing worth a keystroke. The subtlety is that the script itself arrives on
> **stdin**, so a bare `read` would swallow the script's own remaining text. The
> prompt therefore reads `/dev/tty` directly — and if there is no terminal to
> confirm on, the script refuses to wipe rather than proceeding anyway.

> **Why `-fsSL`, not `-sL`?** `-f` makes curl fail loudly on a bad URL instead of
> silently piping a 404 HTML page into `sudo bash` (which then surfaces as the
> baffling `404:: command not found`). Two prompts are still suppressed, because
> neither has a terminal to appear on: `--yes-wipe-all-disks` (disko's wipe
> confirm) and `--no-root-passwd` (nixos-install's root-password prompt).

> **disko is pinned in the script, not in `flake.lock`.** `bootstrap.sh` runs
> from a live ISO, outside the flake, so it cannot inherit the lock.
> `DISKO_REF` near the top of the script is a hand-maintained pin: nothing bumps
> it for you, and nothing fails if it goes stale — the installer just quietly
> stops picking up disko fixes. Resolve candidates with
> `git ls-remote --tags https://github.com/nix-community/disko`, and note that
> output is **not** version-sorted (`v1.9.0` sorts above `v1.13.0` lexically).

When it finishes:

1. In UTM, detach the ISO (Drive → eject).
2. `reboot`.

The VM boots straight into the cage+foot console (autologin). Log in from the Mac
over SSH with your key — next.

## 3. SSH from the Mac

Access is **key-only**: `modules/nixos/dev.nix` sets
`services.openssh.settings.PasswordAuthentication = false`, so the key in `user.nix`
is the _only_ way in over the network — there is no password fallback.

> **sshd is gated behind `local.dev.enable`, not in `common.nix`.** sshd, the
> password-auth lockout and your public key are declared in
> `modules/nixos/dev.nix` and apply to every host that flips `local.dev.enable =
> true` (`nixos` and `geekom`; `hplaptop` leaves it off — no sshd there). A new
> dev host needs nothing added for SSH — verify rather than re-implement:
> `nix eval .#nixosConfigurations.<host>.config.services.openssh.enable`.

1. **Generate a key** on the Mac (skip if you already have one):

    ```sh
    ssh-keygen -t ed25519 -C "you@example.com"
    ```

2. **Put its public half in `user.nix`** as `sshKey = "ssh-ed25519 …";` and commit.
   `modules/nixos/dev.nix` installs it into every dev host's `authorizedKeys` at
   build time, so it must be in the repo _before_ the install in step 2.

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

## Manual install (fallback / reference)

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

> **Why labels?** UUIDs are regenerated on every fresh install.
> `hosts/vm/hardware-configuration.nix` mounts `/` and `/boot` by the labels
> `nixos` and `BOOT`, so it is install-independent — set the labels here and the
> committed hardware config just works. (`hosts/vm/disk-config.nix` sets these
> same labels; disko and this manual path produce an identical layout.)
>
> **The root label is per host.** The VM's root is labelled `nixos`, `geekom`'s
> is labelled `geekom`; the ESP is `BOOT` on both. Each host's
> `disk-config.nix` and `hardware-configuration.nix` have to agree on the pair,
> and both files carry a comment saying so. Note the VM's root label happens to
> match its flake attr while its directory is `hosts/vm` — three names, two of
> which coincide.

**Install straight from the flake** — no `nixos-generate-config`, since the
committed config already carries the by-label mounts, the EFI fix
(`boot.loader.efi.canTouchEfiVariables = false`, the aarch64/UTM fix — UTM's
firmware can't take NVRAM boot-entry writes, so systemd-boot uses its fallback
path), and your SSH key:

```sh
export NIX_CONFIG="experimental-features = nix-command flakes"
nixos-install --flake github:andreaserradev-gbj/dotfiles-nix#<host>   # any host attr
reboot               # detach the install medium first
```

> **The attr is required here, unlike a daily rebuild.** A running system knows
> its own `networking.hostName`, so `nixos-rebuild switch --flake .` resolves the
> host on its own. The live ISO calls itself `nixos` whatever you are installing,
> so any hostname-derived fallback resolves to the VM. Today that fails loudly on
> x86_64 hardware — wrong architecture — but it would quietly pick the wrong
> machine the moment a second x86_64 host exists. Name the host explicitly at
> install time, every time.

> If a fresh VM's disk layout ever differs from the committed template, re-run
> `nixos-generate-config`, re-apply the two by-label mount edits, and commit.

**Stale running shell after a rebuild.** The daily `nixos-rebuild switch` relocates
user binaries (Home Manager `useUserPackages` moves them to
`/etc/profiles/per-user/andrea/bin`), so the shell you ran it in keeps stale `PATH`
entries — you'll see `no such file … /.nix-profile/bin/…`. Open a fresh login shell
(or `ssh` in again). Expected, not a failure. (A fresh install reboots anyway, so
this only bites on daily switches.)

## Shortcut: save a UTM template

Instead of repeating the install, snapshot a base VM once it's installed. Cloning
that template drops you straight at a working system you can `nixos-rebuild` on.

---

- Console behaviour after install: [doc/vm-console.md](vm-console.md)
- Rebuild aliases and daily commands: [doc/workflow.md](workflow.md)
- Common failure modes: [doc/troubleshooting.md](troubleshooting.md)
