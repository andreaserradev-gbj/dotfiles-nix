# dotfiles-nix

Personal NixOS configuration for **three machines built from one flake** — an
Apple Silicon development VM, an x86_64 desktop, and an x86_64 laptop for a
non-technical user. One command rebuilds the system and my `$HOME` on either of
them:

```sh
sudo nixos-rebuild switch --flake .
```

**No host attribute.** `nixos-rebuild` derives it from `networking.hostName`, so
the same command is correct on every host and there is nothing per-host to
remember or mistype.

## The hosts

| attr       | directory           | architecture    | machine                 | console                      |
| ---------- | ------------------- | --------------- | ----------------------- | ---------------------------- |
| `nixos`    | `hosts/vm/`         | `aarch64-linux` | UTM VM on Apple Silicon | cage + foot kiosk, autologin |
| `geekom`   | `hosts/geekom/`     | `x86_64-linux`  | GEEKOM A9 Max mini PC   | GNOME on GDM                 |
| `hplaptop` | `hosts/hplaptop/`   | `x86_64-linux`  | HP laptop (Intel i5)    | vanilla GNOME on GDM         |

> **The VM's two names are not a typo.** Its flake attr is `nixos` because that
> has to match `networking.hostName` — which is what the no-attr rebuild
> resolves against — while its directory is `hosts/vm/`. `bootstrap.sh` carries
> an explicit attr→directory mapping for exactly this reason: deriving
> `hosts/$HOST/` directly would fetch a 404 for the VM alone.

## The model

macOS is the host and stays imperative (always-latest apps, browser, mail).
The VM is the reproducible dev environment — not a daily driver, but the part
worth being able to rebuild from scratch and get back byte-for-byte. `geekom`
is a real desktop that gets sat at, so it runs GNOME and a browser rather than
a terminal kiosk.

Everything lives in a single flake with two layers folded together:

- **System layer** — `modules/nixos/` shared by every host, plus
  `hosts/<host>/default.nix` and `hosts/<host>/hardware-configuration.nix`
- **Home layer** — Home Manager, wired in as a NixOS module (not a standalone
  `home-manager switch`), so one `nixos-rebuild` builds both.

The split is the whole point of the multi-host layout: anything under
`modules/` is shared and moves **both** hosts when it changes, anything under
`hosts/` moves one. `scripts/check-hosts.sh` is how you find out which you just
did — see below.

## Layout

```
flake.nix              nixosConfigurations.nixos (aarch64) + .geekom + .hplaptop (x86_64)
user.nix               personal identity — the one file to edit when forking
home.nix               Home Manager entrypoint — imports modules/home/
hosts/vm/              the aarch64 UTM VM
hosts/geekom/          the x86_64 mini PC
hosts/hplaptop/        the x86_64 HP laptop (non-technical user, no dev tooling)
  default.nix            hostName, stateVersion, hardware, display stack
  hardware-configuration.nix   by-label mounts, initrd modules
  disk-config.nix        disko layout — read by bootstrap.sh only, never imported
modules/nixos/         system layer, shared by every host
  common.nix             users, shell, system packages
  desktop.nix            defines AND consumes the `local.desktop` option
  dev.nix                defines AND consumes the `local.dev` option
modules/home/          one module per tool (zsh, git, neovim, …) — 100% Nix
  maintenance.nix        `nrb`/`ngca` aliases for non-dev hosts (no `nh`)
config/<tool>/…        verbatim assets referenced by the modules (nvim tree,
                       bat theme, fastfetch, zellij) — 100% non-Nix
scripts/check-hosts.sh the multi-host regression gate
templates/devshell/    per-project dev shell template
bootstrap.sh           one-command install of any host, from a live ISO
```

> **`modules/nixos/desktop.nix` is imported by every host, not just `geekom`.**
> It defines the `local.desktop` option as well as consuming it, so every host
> has to see it in order to leave it switched off. A host that cannot see an
> option cannot set it to `false`.

> **`local.desktop.variant` selects the desktop flavour.** `"full"` (the
> default) ships PaperWM + Catppuccin theming via Home Manager; `"vanilla"`
> ships plain GNOME. `geekom` keeps the default; `hplaptop` picks `"vanilla"`
> for a non-technical user. The HM side gates on
> `osConfig.local.desktop.variant == "full"` (see `modules/home/desktop.nix`,
> `modules/home/gtk.nix`), so a vanilla host skips the theming modules
> entirely. `local.desktop.libreoffice.enable` (default `false`) is a
> sub-option only `hplaptop` flips on — Elisa needs Word/Excel for HR work.

> **`modules/nixos/dev.nix` defines AND consumes the `local.dev` option.**
> Like `desktop.nix`, it is imported by every host so every host can see the
> option. It gates nix-ld, ollama, opencode, nodejs, uv, jq, **and** sshd +
> `authorizedKeys` — sshd is dev/admin tooling, not a baseline. `nixos` and
> `geekom` set `local.dev.enable = true`; `hplaptop` leaves it `false`, so it
> has no sshd, no authorized_keys, and none of the dev packages. A
> non-technical user's machine with no admin surface area is the whole
> point of that host.

> **`disk-config.nix` is not part of the running system.** disko is not a flake
> input and neither host imports it; `bootstrap.sh` fetches a copy over HTTPS
> and runs disko standalone against that. The file describes how the disk was
> *created*, not how it is *mounted* — that is
> `hardware-configuration.nix`, which is hand-written and mounts by label.

## Checking both hosts still build

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
should move both hashes; touching `hosts/geekom/` should move exactly one.

## Installing a host

The goal: a brand-new machine ends up as an exact copy of this environment. The
supported path is a **one-command scripted install** (`bootstrap.sh`), which
takes the host as an argument and installs either machine:

```sh
curl -fsSL https://raw.githubusercontent.com/andreaserradev-gbj/dotfiles-nix/main/bootstrap.sh \
  | sudo bash -s -- <host>            # host is `nixos` or `geekom`
```

Boot the NixOS minimal ISO **for the target's own architecture** first —
aarch64 for the VM, x86_64 for `geekom`.

The rest of this section walks the UTM VM end to end. Real hardware has its own
walkthrough — firmware, boot order, wifi carry-over, Bluetooth — under
[Installing on bare metal](#installing-on-bare-metal-geekom).

> **Forking?** Everything personal lives in one file, [`user.nix`](user.nix):
> `username`, `fullName`, `email`, `timeZone`, and `sshKey`. Edit it in your fork
> and commit _before_ installing — `bootstrap.sh` pulls the config from git, so the
> machine is built with whatever identity your pushed `user.nix` carries. Point the
> bootstrap/install URLs below at your fork.

### 1. Create the UTM VM

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

### 2. One-command install

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

### 3. SSH from the Mac

Access is **key-only**: `modules/nixos/common.nix` sets
`services.openssh.settings.PasswordAuthentication = false`, so the key in `user.nix`
is the _only_ way in over the network — there is no password fallback.

> **This is in the shared module, so every host inherits it.** sshd, the
> password-auth lockout and your public key are declared once in
> `modules/nixos/common.nix` and apply to `nixos` and `geekom` alike. A new host
> needs nothing added for SSH — verify rather than re-implement:
> `nix eval .#nixosConfigurations.<host>.config.services.openssh.enable`.

1. **Generate a key** on the Mac (skip if you already have one):

    ```sh
    ssh-keygen -t ed25519 -C "you@example.com"
    ```

2. **Put its public half in `user.nix`** as `sshKey = "ssh-ed25519 …";` and commit.
   `modules/nixos/common.nix` installs it into every host's `authorizedKeys` at
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
nixos-install --flake github:andreaserradev-gbj/dotfiles-nix#<host>   # nixos | geekom
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

### Shortcut: save a UTM template

Instead of repeating the install, snapshot a base VM once it's installed. Cloning
that template drops you straight at a working system you can `nixos-rebuild` on.

## Installing on bare metal (geekom)

The walkthrough above assumes UTM. This is the same install on real hardware,
written down while doing it, in the order it has to happen. Every trap below is
one that actually bit — a future self should not have to re-derive any of it.

### 0. Before you wipe

**A machine that shipped with Windows carries its licence key in firmware.** It
lives in the ACPI **MSDM** table, so it survives a full disk wipe and a clean
Windows ISO will re-activate on the same board. Record the key off-machine
anyway — never in this repo — and check whether the licence is also linked to an
account before you destroy the partition.

> Cloning the factory disk first was considered and rejected. It preserves a
> recovery partition and a driver set that are both redundant once the key
> survives independently, at the cost of an external drive and an hour.

**Read the BIOS and EC versions now and write them down.** You need them for the
next decision, and afterwards they are the only record of what the machine
shipped with.

### 1. Firmware: decide about flashing

**Default to not flashing.** It is the one step here that can brick the board,
and it buys nothing unless it fixes a problem you actually have. Check the
vendor's changelog for the version on offer — if there is none, and often there
is not, that alone is reason enough to decline. For this board the `0.26`
release is reported to fail mid-flash with `Error 18: Secure Flash Rom Verify
Fail`.

This runbook is repeatable. Flash later, if a specific fix ever matters.

**If you do flash, disable Secure Boot _after_ it, not before.** A firmware
update generally restores defaults, and Secure Boot is one of them.

### 2. Get into the firmware setup

**Enter it from Windows rather than key-mashing at POST**: Settings → System →
Recovery → Advanced startup → Restart now → Troubleshoot → Advanced options →
UEFI Firmware Settings.

> **Disable Fast Boot first thing.** Fast Boot skips USB enumeration at POST.
> That is why the `DEL` window is unusable *and* why a perfectly good install
> stick appears not to exist. Two baffling symptoms, one cause.

> **`[USB Key]` in the boot order is not your ISO.** A NixOS ISO written with
> `dd` is isohybrid: it carries an MBR with a `0xEF` ESP, so AMI firmware
> classifies it as **USB Hard Disk**, not USB Key. Setting Boot Option #1 to
> `[USB Key]` looks right and silently does nothing. Use the **F7** one-time boot
> menu, which lists the stick by name immediately, or set Boot Option #1 to
> `[USB Hard Disk]`.

### 3. Write and boot the ISO

Write the **x86_64** minimal ISO — not the aarch64 one the VM uses. Verify its
SHA256 before writing, verify the stick after, and label it physically; an
unlabelled USB stick is indistinguishable from every other one in the drawer.

Boot it with **F7**.

### 4. Bring up the network on the live ISO

Ethernet needs nothing. For wifi:

```sh
rfkill unblock wifi
nmtui                       # pick the SSID, enter the password
ping -c3 nixos.org
```

> **The wifi hardware works with no configuration**, because
> `hardware.enableRedistributableFirmware` is set in the shared module and the
> ISO ships the same blobs. What is *not* automatic is the SSID and password —
> those are deliberately absent from this repo, because it is public.

### 5. Capture the hardware facts while the machine is open

This is the cheapest moment to record what is actually fitted.

> **`dmidecode` is not on the minimal ISO.** Fetch it for the duration:
>
> ```sh
> nix-shell -p dmidecode --run 'sudo $(which dmidecode) -t 17'    # memory
> ```
>
> Roughly a 100 MiB download, so do it while the network is up. **`sudo` resets
> `PATH`**, so the nix-shell-provided binary has to be named by absolute path,
> and the single quotes are what stop `$(which …)` expanding in the outer shell,
> where it does not exist yet.

Take the disk's stable path from `ls -l /dev/disk/by-id/`. Prefer the
**model/serial** form (`nvme-<MODEL>_<SERIAL>`) over the opaque `nvme-eui.…`
alias. udev publishes several aliases for one device and all of them are stable,
but only the model/serial form is recognisable to a human reading a diff — which
is precisely when a wrong disk needs spotting.

### 6. Install

Put the real by-id path into `hosts/geekom/disk-config.nix`, then **commit and
push before installing** — `bootstrap.sh` fetches the layout from GitHub, not
from your working tree. A forgotten push fails safely: the script refuses to run
against a `PLACEHOLDER` path.

```sh
curl -fsSL https://raw.githubusercontent.com/andreaserradev-gbj/dotfiles-nix/main/bootstrap.sh \
  | sudo bash -s -- geekom
```

Unplug the USB stick, then reboot.

### 7. Carry the wifi profile across, or retype it

The installed system does not inherit the live ISO's network. Either retype it
with `nmtui` after first boot, or copy the profile across before rebooting,
while the installed root is still mounted at `/mnt`:

```sh
sudo sh -c 'cp -a /etc/NetworkManager/system-connections/*.nmconnection \
  /mnt/etc/NetworkManager/system-connections/'
```

> **The `sudo sh -c '…'` wrapper is load-bearing, and this is the most dangerous
> line in the runbook to get wrong.** `/etc/NetworkManager/system-connections/`
> is mode `700 root:root`, so an unprivileged shell cannot expand
> `*.nmconnection` at all. Writing `sudo cp -a /etc/…/*.nmconnection …` hands the
> *literal* glob to `cp` and fails. The expansion has to happen inside the
> privileged shell. An SSID containing spaces survives this fine — glob results
> are not word-split.

After the reboot, verify: `nmcli connection show`, and
`ls -l /etc/NetworkManager/system-connections/` should read `600 root:root`.

### 8. First boot

```sh
hostname                                   # geekom
uname -m                                   # x86_64
readlink -f /run/current-system
ls /nix/var/nix/profiles/ | grep system-
```

> **Prove the running system came from this flake.** Evaluate
> `.#nixosConfigurations.geekom.config.system.build.toplevel` and check it is the
> **same store path** as `/run/current-system`. That equality is proof. A
> rebuild that merely succeeded is not.

**Change the password immediately.** `modules/nixos/common.nix` sets
`initialPassword`, and this repo is public — until you change it, the login
password is written down on the internet. `initialPassword` applies only at
account creation, and `users.mutableUsers` is left at its default of `true`, so
a `passwd` change persists across every rebuild.

> **Changing it with `passwd` desyncs the GNOME login keyring**, and the failure
> is delayed and confusing: the desktop keeps asking for a password you no longer
> use. `/etc/pam.d/passwd` contains only `pam_unix`, so nothing re-encrypts the
> keyring when the Unix password changes. Either change the password **before**
> first launching a browser — so the keyring is created under the right password
> and never needs re-keying — or re-key it afterwards in Passwords and Keys
> (seahorse): Login keyring → Change Password.

### 9. Bluetooth — a wired mouse or keyboard is required here

```sh
systemctl status bluetooth       # active
bluetoothctl list                # an adapter must appear
rfkill list bluetooth            # neither soft nor hard blocked
```

> **An adapter appearing is the proof the Bluetooth firmware loaded.** Wi-Fi and
> Bluetooth are separate devices on the same combo radio, so working Wi-Fi does
> not imply working Bluetooth. `rfkill unblock bluetooth` if either block is set.

Pair from GNOME Settings → Bluetooth, driving it with the wired mouse. Keyboard
only:

```sh
bluetoothctl
  power on
  scan on
  pair <mac>
  trust <mac>
  connect <mac>
```

> **`trust` is the step everyone skips, and skipping it looks like success.**
> Confirm `bluetoothctl info <mac>` reports `Trusted: yes`, then **reboot and
> check the mouse reconnects unaided** before unplugging the wired one. Without
> `trust`, pairing works perfectly until the first reboot or the first flick of
> the mouse's power switch, then silently refuses.

### 10. SSH, in both directions

**Inbound, from the Mac.** Nothing needs adding to the NixOS config — sshd, the
password-auth lockout and your key all arrive from `modules/nixos/common.nix`.
What you do need is to clear the stale host key:

```sh
ssh-keygen -R <address>          # on the Mac, before the first connection
```

> **The same address presents two different host keys across this runbook.** The
> live ISO has its own ephemeral key and accepts a password; the installed system
> generates a fresh one and is key-only. If you accepted the ISO's key earlier,
> ssh will refuse the installed system with a MITM warning. Remove the stale
> entry — do **not** reach for the VM's `StrictHostKeyChecking no`. Verify the new
> fingerprint against the console with
> `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` if you want it done properly.

Add a `Host` block to the Mac's `~/.ssh/config`:

```
Host geekom
  HostName <the reserved address>
  User <username>
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ServerAliveInterval 60
  ServerAliveCountMax 3
```

> **Do not copy the `Host nixos` block.** It carries `StrictHostKeyChecking no`,
> `UserKnownHostsFile /dev/null` and `LogLevel ERROR`, safe only because the VM
> is a throwaway on a private vmnet whose host key churns. This is a real machine
> on a real LAN — those three lines would disable host-key verification on the
> one host where it actually matters.

> **Pin the address with a DHCP reservation on the router**, keyed to the MAC
> from `ip link`. The VM can hardcode an IP because UTM's vmnet assigns
> deterministically; a LAN lease has no such guarantee and **will** move — after
> which the alias, and every `known_hosts` entry, points at whatever device took
> the address over. If the router is not yours to configure, the declarative
> alternative is `services.avahi` with `publish.addresses = true`, reaching the
> box as `<host>.local` — note that is **not** in the flake today, so it is a
> config change plus a rebuild, not just a router setting.

**Outbound, to GitHub.** Generate the box its own keypair and add the public half
to your account:

```sh
ssh-keygen -t ed25519
ssh -T git@github.com
```

> **Do this _before_ cloning the repo, not after.** The clone then comes out with
> a working SSH push remote instead of needing a later `git remote set-url` off
> HTTPS. `ssh -T` is also the check that catches adding the key to the wrong
> GitHub account.
>
> **The private half must never enter this repo.** It is public.

### 11. Suspend does not work on this machine — turn it off

```sh
cat /sys/power/mem_sleep
```

If that prints `[s2idle]` and nothing else, the machine has no suspend-to-RAM.
The firmware advertises `S0 S4 S5` — S0ix, hibernate, soft-off — and **no S3**.
Confirmed empirically: it enters s2idle and never returns, the journal ends
mid-suspend with no line after it, and the power button is the only way out.

**Do not add `mem_sleep_default=deep`.** `deep` is not in `mem_sleep`, so the
parameter is a silent no-op — it looks like a fix and changes nothing.

Turn automatic suspend off instead: Settings → Power → Automatic Suspend → Off.

> **That stops the timer, not the menu.** The power menu's Suspend entry still
> works, and would still hang the machine. Masking
> `systemd.targets.{sleep,suspend,hibernate,hybrid-sleep}` makes it impossible,
> at the cost of also blocking hibernate — which the firmware does support, but
> which needs swap this disk layout does not create.

### What a reinstall does not restore

Everything above rebuilds itself from the flake. These do not. They are grouped
by **how you get them back**, which is the only grouping that helps at 11pm:

| state               | recovery                                                                                                                                            |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Wifi password       | Retype at `nmtui`. Absent from this repo deliberately — it is public.                                                                                |
| GitHub key          | Regenerate on the box **and** re-add the public half to GitHub. Forgetting the second half fails confusingly.                                         |
| Bluetooth pairings  | `/var/lib/bluetooth` is not in this repo. Every pairing is lost and every device must be re-paired — which is why a wired mouse or keyboard is needed. |
| Application state   | Browser profiles, credential stores, anything you signed into. It lives outside this repo and does not survive a reinstall.                            |

The first three take minutes if you know they are coming and cost an evening if
you do not. Listing them is the whole point.

## Installing on bare metal (hplaptop)

The geekom walkthrough above covers a generic bare-metal install in detail.
This section is the **delta** for the HP laptop — what differs, not what is the
same. The HP laptop is a vanilla install with no GPU traps, so it is shorter;
the one caveat that is real here is **suspend**.

The host is for a non-technical user (Elisa). The design constraints follow
from that:

- **No dev tooling, no sshd.** `local.dev.enable = false` in
  `hosts/hplaptop/default.nix` (explicit). The `dev.nix` seam gates nix-ld,
  ollama, opencode, nodejs, uv, jq, **and** sshd + authorized_keys — all off.
- **Vanilla GNOME**, not PaperWM + Catppuccin. `local.desktop.variant =
  "vanilla"` skips the HM theming modules (see the callout above).
- **LibreOffice enabled** (`local.desktop.libreoffice.enable = true`) — Elisa
  needs Word/Excel for HR work.
- **Bash shell, not zsh.** `users.users.elisa.shell = lib.mkForce pkgs.bash`
  overrides `common.nix`'s bare `pkgs.zsh` (priority 50 beats 1500).
- **Email in Brave, not Thunderbird.** Elisa's email is configured directly in
  Brave with her Google account. There is no `email` field in her `user.nix`
  entry and no `modules/home/mail.nix`.
- **Wi-Fi powersave on.** `networking.networkmanager.wifi.powersave =
  lib.mkForce true` — a laptop trades a little latency for battery life, the
  opposite tradeoff from the mains-powered geekom box.
- **No `sshKey` in `user.nix`.** sshd is off, so nothing consumes it. Andrea
  maintains this box on-site; Elisa updates via `nrb` (see below).

### Before you wipe

Record the Windows licence key from the ACPI MSDM table (see the geekom
section). Read the BIOS/EC versions. The HP laptop's firmware is not the
geekom firmware — do not assume the same quirks, but the same cautions apply.

### Firmware

Default to not flashing (same reasoning as geekom). If you do flash, disable
Secure Boot _after_, not before.

### Install

The install is the same four-phase `bootstrap.sh` flow as geekom:

```sh
curl -fsSL https://raw.githubusercontent.com/andreaserradev-gbj/dotfiles-nix/main/bootstrap.sh \
  | sudo bash -s -- hplaptop
```

Two things must be done first, both before booting the ISO:

1. **Fill in the real disk device** in `hosts/hplaptop/disk-config.nix`
   (replace `/dev/disk/by-id/PLACEHOLDER` with the real by-id node from
   `ls -l /dev/disk/by-id/`). Commit and push — `bootstrap.sh` fetches the
   layout from GitHub, and refuses to run against a `PLACEHOLDER` path.
2. **Fill in the initrd modules** in
   `hosts/hplaptop/hardware-configuration.nix`. Run
   `nixos-generate-config --no-filesystems --dir /tmp/cfg` on the booted ISO
   and copy the `boot.initrd.availableKernelModules` list into the committed
   file. The shipped template ships an empty list — it will not boot on real
   hardware as-is. `boot.kernelModules = [ "kvm-intel" ]` is already set (this
   is an Intel box, not AMD).

The by-label mounts (`/` → `hplaptop`, `/boot` → `BOOT`) are hand-written and
must match the labels `disk-config.nix` creates. disko and the committed
hardware config agree by construction; verify rather than re-derive.

> **Intel, not AMD.** `hardware.cpu.intel.updateMicrocode = true` (not
> `hardware.cpu.amd`), and there is no `hardware.amdgpu.initrd.enable`. The
> HP laptop has an Intel i5 with integrated graphics — no discrete GPU, no
> AMD-specific firmware.

### After first boot

```sh
hostname                                   # hplaptop
uname -m                                   # x86_64
readlink -f /run/current-system
```

> **Prove the running system came from this flake.** Evaluate
> `.#nixosConfigurations.hplaptop.config.system.build.toplevel` and check it
> is the **same store path** as `/run/current-system`.

**Change the password immediately.** `modules/nixos/common.nix` sets
`initialPassword`, and this repo is public. The GNOME login keyring caveat
from the geekom section applies here too — change the password before
launching a browser, or re-key the keyring in seahorse afterwards.

**Elisa's email.** Configure her Google account directly in Brave — there is
no Thunderbird on this host and no `email` field in `user.nix`.

### Suspend — verify before unmasking

Suspend is **masked by default** on this host:

```nix
systemd.targets = {
  sleep.enable = false;
  suspend.enable = false;
  hibernate.enable = false;
  hybrid-sleep.enable = false;
};
```

The geekom box proved that "the firmware advertises S-states" is not evidence
that resume works — its resume hangs hard with the journal stopping mid-suspend.
The same class of quirk can hit any machine. Until this specific laptop has
been observed to suspend and resume cleanly, the mask stays.

**To verify on-site:**

```sh
# As root (or sudo):
systemctl suspend          # wait ~10s, then wake via power button or lid open
journalctl -k -b -1         # look for a clean suspend → resume cycle
```

If the resume is clean (the journal picks up after the suspend line, the
desktop comes back, networking reconnects), remove the `systemd.targets` block
from `hosts/hplaptop/default.nix`, rebuild, and commit. If it hangs, leave the
mask in place — Elisa is non-technical, and a hard hang is a brick from her
perspective. Suspend is a nice-to-have, not a requirement.

> **The mask covers GDM's greeter too.** GNOME Settings → Power → Automatic
> Suspend writes to the logged-in user's dconf, but GDM's greeter runs as its
> own user with its own 900s idle timer — that is exactly how the geekom box
> was lost (nobody logged in, greeter suspended 15 minutes after boot).
> Masking the targets is the only form that covers the greeter, every user
> session, and the power menu entry. See `hosts/geekom/default.nix:56-81` for
> the full reasoning.

### Updating the system

Elisa has no local clone of this repo and no `nh`. Updates go through a single
bash alias, `nrb`, defined in `modules/home/maintenance.nix` (gated on
`!osConfig.local.dev.enable`, so it only appears on non-dev hosts):

```sh
nrb           # nixos-rebuild boot --flake github:andreaserradev-gbj/dotfiles-nix
```

`boot` (not `switch`) so a kernel or display-stack change does not tear down
the running session — a reboot applies it. Andrea runs a full `nixos-rebuild`
on-site visits; Elisa just runs `nrb` and reboots when prompted.

> **No SSH on this host.** sshd is gated behind `local.dev.enable`, which is
> false here. There is no network rebuild path and no authorized_keys entry.
> Maintenance is either `nrb` (Elisa) or on-site (Andrea).

### What a reinstall does not restore

Same set as geekom — wifi password, Bluetooth pairings, browser profiles,
LibreOffice state. All live outside this repo. See the geekom table above.

## Daily workflow

Rebuild aliases (defined in `modules/home/shell.nix`). They are fronted by
[`nh`](https://github.com/nix-community/nh), a nicer `nixos-rebuild`/GC
front-end. `NH_FLAKE` points at this repo, so **none of them need a path or a
host argument** — the same alias is correct on both machines.

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

### Which rebuild command, and from where

`nrs` runs in two phases: `switch-to-configuration test` first, then setting the
system profile and `switch-to-configuration boot`. That order is a feature — a
config that cannot activate never becomes the boot default.

The hazard is that phase 1 can restart the display stack, and so tear down the
session `nrs` is running in. It then dies between the two phases, leaving the
activation applied with **no new generation, no bootloader entry and no error
text**.

| situation                        | use                            | why                                                                   |
| -------------------------------- | ------------------------------ | --------------------------------------------------------------------- |
| normal case, SSH available       | `nrp`, then `nrs` **over SSH** | the SSH session is its own scope, so a display restart cannot reap it  |
| at the machine's console, no SSH | `nrp`, then `nrb`, then reboot | `nrb` never runs phase 1, so there is nothing to self-destruct against |
| kernel moved                     | reboot regardless              | `switch` cannot load a new kernel                                      |

> **Never run `nrs` from a machine's own graphical console.** True on both hosts,
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

## Per-project dev environments

Per-project toolchains live _with each project_ as a Nix dev shell that direnv
loads automatically on `cd` — no global installs, no `nvm use`, every repo pins
its own versions. The starting point is a flake template in this repo
(`templates/devshell/`, exposed as the `devshell` flake output), so a new
project is one command away:

```bash
cd ~/code/my-project
nfi                   # alias: nix flake init -t ~/dotfiles-nix#devshell
$EDITOR flake.nix     # add tools to `packages`, e.g. [ nodejs_24 ]
git add flake.nix     # flakes only see tracked files — stage before evaluating
direnv allow          # one-time trust; the shell now auto-loads on cd
```

Whatever you added (`node`, …) is now on `PATH` inside the project and gone
outside it. The template pins nixpkgs to `nixos-26.05` — the same release as
this system flake — so dev shells reuse store paths already on disk instead of
re-downloading a second nixpkgs.

> Commit the generated `flake.lock` too: it pins the exact nixpkgs revision, so
> the shell is reproducible for anyone who builds the project.

The VM is headless, so reach a dev server from the Mac by forwarding its port
over SSH:

```bash
# on the Mac
ssh -L 5173:[::1]:5173 nixos    # then open http://localhost:5173
```

> **Vite binds IPv6.** Vite resolves `localhost` to `::1`, not `127.0.0.1`, so
> the forward target must be the v6 loopback `[::1]` — `-L 5173:localhost:5173`
> (or `127.0.0.1`) gives a blank page.

Gotchas:

- **Flakes ignore untracked files.** A new `flake.nix` is invisible to
  evaluation until it's `git add`ed — the error reads "path does not exist,"
  not "you forgot to stage." Modern Nix auto-marks untracked files as
  intent-to-add as a safety net, but that stages an _empty_ placeholder, so a
  real `git add` is still required to commit content.
- **`direnv allow` is one-time per project.** direnv never runs an `.envrc` it
  hasn't been told to trust, and only re-prompts when the file changes — a
  security boundary, since an `.envrc` runs arbitrary shell.
- **Non-interactive SSH gets no dev shell.** direnv's auto-load hooks the
  _interactive_ prompt only, so `ssh nixos 'cd proj && node …'` won't find the
  tools. Enter the shell explicitly: `nix develop --command node …`.
- **Gitignore `.direnv/`.** nix-direnv caches the evaluated environment there;
  it's machine-local and must never be committed.
- **Commit `.envrc` — unless it holds secrets.** The guarded `.envrc`
  (`if has nix; then use flake; fi`) is safe to commit and makes the shell
  reproducible on clone. But when a project uses `.envrc` to load a token
  (`export GH_TOKEN=…`), keep it gitignored — or move the secret into a
  gitignored `.env` and `dotenv_if_exists` it from a committed `.envrc`.

## Gotchas

- **`git add` before `--flake`.** See above — the single most common footgun.
- **`/etc/nixos/*` is vestigial once you're on `--flake`.** A plain
  `nixos-rebuild` (no `--flake`) reads `/etc/nixos/`, but every alias here
  passes `--flake`, so this repo is authoritative. After the first successful
  flake switch you can delete the stale files to enforce a single source of
  truth (see below).
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

## Local console (cage + foot) — the VM only

The UTM window boots straight into a full-screen [foot](https://codeberg.org/dnkl/foot)
terminal — autologin, no display manager — via [cage](https://github.com/cage-kiosk/cage),
a single-app kiosk Wayland compositor. This is a _local_ console for when SSH or
networking is down (or during a bad rebuild), **not** a second workspace: the real
dev loop stays SSH-from-the-Mac (see below). Everything is software-rendered — the
VM has no usable GPU.

Two layers, one rebuild:

- **System** (`hosts/vm/default.nix`) — `services.cage` (compositor + autologin),
  `services.spice-vdagentd`, and the `video=` display mode.
- **Home** (`modules/home/foot.nix`, `modules/home/fonts.nix`,
  `modules/home/starship.nix`) — the terminal, its fonts, and the prompt.

### Why these pieces

- **cage, not a desktop.** cage shows exactly one full-screen program and _is_ the
  login: its systemd unit (`cage-tty1`) conflicts with `getty@tty1` and autologins
  through a PAM null-password session. No greetd, no display manager.
- **foot, not kitty/alacritty.** foot rasterizes glyphs purely on the CPU — no
  OpenGL/EGL — so it's the one terminal that works on a GPU-less guest. GL-based
  terminals may not even start under software rendering.
- **`WLR_RENDERER = "pixman"` (mandatory).** Forces wlroots' pure-CPU renderer.
  `WLR_RENDERER_ALLOW_SOFTWARE=1` (GLES2-on-llvmpipe) is _not_ enough here — EGL
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

The GUI-in-VM is _only_ the terminal. Editing, the browser, and the dev loop stay
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
- **Console resolution is set host-side, not in this repo.** cage (wlroots)
  always uses the mode the host advertises as _preferred_ — `1280x800` unless
  told otherwise. The fix is the pair of `-global virtio-gpu-pci.xres/yres`
  QEMU arguments from the UTM setup step; a one-time UTM setting that cannot be
  made declarative here. Guest-side levers do NOT work, don't re-attempt them:
  `video=Virtual-1:…` in `boot.kernelParams` only sizes the pre-cage _text_
  console; cage ignores `wlr-randr` mode/scale requests and has no output-scale
  knob; forcing an EDID via `drm.edid_firmware` empties the virtio-gpu mode
  list and kills the display outright ("Display output is not active" — SSH
  still works, revert and reboot to recover). Text size lives in
  `modules/home/foot.nix` (`font = …:size=`).
