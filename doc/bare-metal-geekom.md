# Installing on bare metal — geekom

The VM walkthrough ([doc/install-vm.md](install-vm.md)) assumes UTM. This is the
same install on real hardware, written down while doing it, in the order it has
to happen. Every trap below is one that actually bit — a future self should not
have to re-derive any of it.

The hplaptop has its own delta document,
[doc/bare-metal-hplaptop.md](bare-metal-hplaptop.md) — it refers back to this one
for everything the two machines share.

## 0. Before you wipe

**A machine that shipped with Windows carries its licence key in firmware.** It
lives in the ACPI **MSDM** table, so it survives a full disk wipe and a clean
Windows ISO will re-activate on the same board. Record the key off-machine
anyway — never in this repo — and check whether the licence is also linked to
an account before you destroy the partition.

> Cloning the factory disk first was considered and rejected. It preserves a
> recovery partition and a driver set that are both redundant once the key
> survives independently, at the cost of an external drive and an hour.

**Read the BIOS and EC versions now and write them down.** You need them for
the next decision, and afterwards they are the only record of what the machine
shipped with.

## 1. Firmware: decide about flashing

**Default to not flashing.** It is the one step here that can brick the board,
and it buys nothing unless it fixes a problem you actually have. Check the
vendor's changelog for the version on offer — if there is none, and often there
is not, that alone is reason enough to decline. For this board the `0.26`
release is reported to fail mid-flash with `Error 18: Secure Flash Rom Verify
Fail`.

This runbook is repeatable. Flash later, if a specific fix ever matters.

**If you do flash, disable Secure Boot _after_ it, not before.** A firmware
update generally restores defaults, and Secure Boot is one of them.

## 2. Get into the firmware setup

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

## 3. Write and boot the ISO

Write the **x86_64** minimal ISO — not the aarch64 one the VM uses. Verify its
SHA256 before writing, verify the stick after, and label it physically; an
unlabelled USB stick is indistinguishable from every other one in the drawer.

Boot it with **F7**.

## 4. Bring up the network on the live ISO

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

## 5. Capture the hardware facts while the machine is open

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

## 6. Install

Put the real by-id path into `hosts/geekom/disk-config.nix`, then **commit and
push before installing** — `bootstrap.sh` fetches the layout from GitHub, not
from your working tree. A forgotten push fails safely: the script refuses to run
against a `PLACEHOLDER` path.

```sh
curl -fsSL https://raw.githubusercontent.com/andreaserradev-gbj/dotfiles-nix/main/bootstrap.sh \
  | sudo bash -s -- geekom
```

Unplug the USB stick, then reboot.

## 7. Carry the wifi profile across, or retype it

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

## 8. First boot

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

## 9. Bluetooth — a wired mouse or keyboard is required here

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

## 10. SSH, in both directions

**Inbound, from the Mac.** Nothing needs adding to the NixOS config — sshd, the
password-auth lockout and your key all arrive from `modules/nixos/dev.nix`
(gated behind `local.dev.enable`, which is true on `geekom`).
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

> **Do not copy the `Host nixos` block.** It carries `StrictHostKeyChecking no`
> and `UserKnownHostsFile /dev/null`, safe only because the VM is a throwaway on
> a private vmnet whose host key churns. This is a real machine on a real LAN —
> those two lines would disable host-key verification on the one host where it
> actually matters.

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

## 11. Suspend does not work on this machine — turn it off

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
> which needs swap this disk layout does not create. The full reasoning lives in
> `hosts/geekom/default.nix` (the `systemd.targets` block and its comment).

## What a reinstall does not restore

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

---

- VM install path: [doc/install-vm.md](install-vm.md)
- hplaptop delta: [doc/bare-metal-hplaptop.md](bare-metal-hplaptop.md)
- Rebuild aliases: [doc/workflow.md](workflow.md)
