# Installing on bare metal — geekom

The VM walkthrough ([doc/install-vm.md](install-vm.md)) assumes UTM. This is the
same install on real hardware, in the order it has to happen. The traps below are
the ones that bit on the way through, plus the ones the flake's own code leaves
in the path — a future self should not have to re-derive any of it.

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
is not, that alone is reason enough to decline.

What follows is this board's — the GEEKOM A9 Max. Its `0.26` release is reported
to fail mid-flash with `Error 18: Secure Flash Rom Verify Fail`. The hplaptop's
firmware is a different vendor's, with its own quirks
([doc/bare-metal-hplaptop.md](bare-metal-hplaptop.md)) — do not flash by default,
and disable Secure Boot afterwards, are all the two machines share.

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
> `hosts/geekom/default.nix` sets `hardware.enableRedistributableFirmware` and
> the ISO enables all hardware (`hardware.enableAllHardware`), so the blobs are
> on both. What is *not* automatic is the SSID and password — those are
> deliberately absent from this repo, because it is public.

## 5. Capture the hardware facts while the machine is open

This is the cheapest moment to record what is actually fitted.

> **`dmidecode` is not on the minimal ISO.** Fetch it for the duration:
>
> ```sh
> nix-shell -p dmidecode --run 'sudo $(which dmidecode) -t 17'    # memory
> ```
>
> One small package — the ISO already carries its own nixpkgs channel, so
> nothing big is fetched — but it still needs the network up. **`sudo` resets
> `PATH`**, so the nix-shell-provided binary has to be named by absolute path,
> and the single quotes are what stop `$(which …)` expanding in the outer shell,
> where it does not exist yet.

Take the disk's stable path from `ls -l /dev/disk/by-id/`. Prefer the
**model/serial** form (`nvme-<MODEL>_<SERIAL>`) over the opaque `nvme-eui.…`
alias. udev publishes several aliases for one device and all of them are stable,
but only the model/serial form is recognisable to a human reading a diff — which
is precisely when a wrong disk needs spotting.

## 6. Install

The committed layout already carries this board's real by-id path — confirm it
against `ls -l /dev/disk/by-id/` on the machine in front of you, and on any
other board replace it. Then **commit and push before installing** —
`bootstrap.sh` reads that layout from GitHub, not from your working tree; a
forgotten push fails safely, because the script refuses to run against a
`PLACEHOLDER` path ([doc/install-vm.md](install-vm.md), section 2).

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
sudo sh -c 'install -d -m 700 /mnt/etc/NetworkManager/system-connections &&
  cp -a /etc/NetworkManager/system-connections/*.nmconnection \
    /mnt/etc/NetworkManager/system-connections/'
```

> **The `sudo sh -c '…'` wrapper is load-bearing, and this is the most dangerous
> line in the runbook to get wrong.** `/etc/NetworkManager/system-connections/`
> is mode `700 root:root`, so an unprivileged shell cannot expand
> `*.nmconnection` at all. Writing `sudo cp -a /etc/…/*.nmconnection …` hands the
> *literal* glob to `cp` and fails. The expansion has to happen inside the
> privileged shell. An SSID containing spaces survives this fine — glob results
> are not word-split.
>
> **`install -d` is the second half of that.** The installed root has no
> `system-connections` directory yet — a tmpfiles rule
> (`d /etc/NetworkManager/system-connections 0700 root root -`) creates it at
> first boot — so `cp` aimed at it fails with a bare "not a directory". The mode
> has to be the `700` tmpfiles would have set.

After the reboot, verify: `nmcli connection show`, and
`ls -l /etc/NetworkManager/system-connections/` should read `600 root:root`.

## 8. First boot

```sh
hostname                                   # geekom
uname -m                                   # x86_64
readlink -f /run/current-system
ls /nix/var/nix/profiles/ | grep system-
```

> **Prove the running system came from this flake.** From any machine with the
> flake:
>
> ```sh
> nix eval --raw github:andreaserradev-gbj/dotfiles-nix#nixosConfigurations.geekom.config.system.build.toplevel
> ```
>
> That store path must be the **same** as `readlink -f /run/current-system` on
> the box. The equality is proof; a rebuild that merely succeeded is not.

**Change the password immediately.** `modules/nixos/common.nix` sets
`initialPassword`, and this repo is public — until you change it, the login
password is written down on the internet. `initialPassword` applies only at
account creation, and `users.mutableUsers` is left at its default of `true`, so
a `passwd` change persists across every rebuild.

> **Changing it with `passwd` desyncs the GNOME login keyring**, and the failure
> is delayed and confusing: the desktop keeps asking for a password you no longer
> use. `/etc/pam.d/passwd` has no `pam_gnome_keyring` entry, so nothing
> re-encrypts the keyring when the Unix password changes. Either change the
> password **before** first launching a browser — so the keyring is created under
> the right password and never needs re-keying — or re-key it afterwards in
> Passwords and Keys (seahorse): Login keyring → Change Password.

**Re-key sops before the first rebuild.** A rebuild that activates (`nrs`,
`nrt`) decrypts `secrets/andrea/` with the machine's own SSH host key, so on a
host that is not yet a `.sops.yaml` recipient it fails outright — and a fresh
install generates a fresh `/etc/ssh/ssh_host_ed25519_key`. Add it and re-wrap
the ciphertext with the recipe in [doc/secrets.md](secrets.md).

**Re-pin the two literals in `hosts/geekom/default.nix`, in the same commit.**
`hostKey` is that same new host public key
(`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`), and `authorizedKey` is this
host's own `~/.ssh/id_ed25519.pub` — the keypair §10 generates. Both are
hand-pinned literals, so a reinstall leaves them stale and `nrs`/`nrt` stop at
host-key verification until they are updated and committed.

## 9. Bluetooth — a wired mouse or keyboard is required here

```sh
systemctl status bluetooth       # active
bluetoothctl list                # an adapter must appear
rfkill list bluetooth            # neither soft nor hard blocked
```

> **An adapter appearing is the proof the Bluetooth firmware loaded.** Wi-Fi and
> Bluetooth are separate devices on the same combo radio, so working Wi-Fi does
> not imply working Bluetooth. `rfkill unblock bluetooth` if either block is set.

Pair from GNOME Settings → Bluetooth, driving it with the wired mouse. If the
wired mouse itself is dead after a cold boot, that is the separate xHCI
enumeration failure, not Bluetooth: `hosts/geekom/usb-mouse-recovery.nix` bounces
the controller at boot when it is missing, and
[doc/troubleshooting.md](troubleshooting.md) has the check. Keyboard only:

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

**Inbound, from the Mac.** sshd and the password-auth lockout come from the dev
gate, and the authorized key from `sshKey` in `user.nix` — documented once in
[doc/install-vm.md](install-vm.md), section 3. That field is **absent** today, so
a freshly installed geekom has an empty authorized-keys list and is reachable
only from its own console until a key is enrolled there.
What you also need is to clear the stale host key:

```sh
ssh-keygen -R <address>          # on the Mac, before the first connection
```

> **The same address presents two different host keys across this runbook.** The
> live ISO has its own ephemeral key and takes a password once an account there
> has one (`passwd`); the installed system generates a fresh one and is key-only.
> If you accepted the ISO's key earlier,
> ssh will refuse the installed system with a MITM warning. Remove the stale
> entry. Verify the new fingerprint against the console with
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

> **Do not copy the `Host nixos` block.** Its `StrictHostKeyChecking no` and
> `UserKnownHostsFile /dev/null` are safe only on the throwaway VM
> ([doc/install-vm.md](install-vm.md), section 3) — on this real LAN they would
> disable host-key verification where it actually matters.

> **Pin the address with a DHCP reservation on the router**, keyed to the MAC
> from `ip link`. The VM can hardcode an IP because UTM's vmnet assigns
> deterministically; a LAN lease has no such guarantee and **will** move — after
> which the alias, and every `known_hosts` entry, points at whatever device took
> the address over. If the router is not yours to configure, the declarative
> alternative is mDNS: avahi is already on for printer and scanner discovery
> (`modules/nixos/desktop.nix`), but with publishing disabled, so `<host>.local`
> resolves nowhere today — `services.avahi.publish.enable = true` is what makes
> `publish.addresses = true` take effect, which is a config change plus a
> rebuild, not just a router setting.

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

## 11. Suspend does not work on this machine — verify it stays off

Nothing to set here: `hosts/geekom/default.nix` masks
`systemd.targets.{sleep,suspend,hibernate,hybrid-sleep}`. This is the check that
the mask landed.

```sh
cat /sys/power/mem_sleep            # [s2idle] and nothing else: no suspend-to-RAM
systemctl is-enabled sleep.target suspend.target hibernate.target hybrid-sleep.target
                                    # masked, masked, masked, masked
```

`mem_sleep` printing `[s2idle]` and nothing else means the machine has no
suspend-to-RAM: the firmware advertises `S0 S4 S5` — S0ix, hibernate, soft-off —
and **no S3**, and entering s2idle never returns (the journal ends mid-suspend
with no line after it, and the power button is the only way out). Hibernate and
hybrid-sleep cost nothing to mask: both need swap, and this disk layout creates
none. The full reasoning lives in `hosts/geekom/default.nix` (the
`systemd.targets` block and its comment).

**Do not add `mem_sleep_default=deep`.** `deep` is not in `mem_sleep`, so the
parameter is a silent no-op — it looks like a fix and changes nothing.

## What a reinstall does not restore

Everything above rebuilds itself from the flake. These do not. They are grouped
by **how you get them back**, which is the only grouping that helps at 11pm:

| state               | recovery                                                                                                                                            |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Login password      | Back to `initialPassword` from `modules/nixos/common.nix`. Change it again immediately — and before launching a browser, for the keyring's sake (§8). |
| GNOME keyring       | `~/.local/share/keyrings` lives on this machine only, and a new one is created under whatever password the account has at that moment — §8's ordering is what keeps it in sync. |
| Wifi password       | Retype at `nmtui`. Absent from this repo deliberately — it is public.                                                                                |
| SSH keys            | Both are new: `/etc/ssh/ssh_host_ed25519_key` from the installer, `~/.ssh/id_ed25519` from §10. Re-add the public half to GitHub, re-pin `hostKey`/`authorizedKey` (`hosts/geekom/default.nix`) and re-key sops — §8. |
| Bluetooth pairings  | `/var/lib/bluetooth` is not in this repo. Every pairing is lost and every device must be re-paired — which is why a wired mouse or keyboard is needed. |
| Thunderbolt docks   | `/var/lib/boltd` holds each authorization; every display or dock needs `boltctl enroll --policy auto` again ([doc/troubleshooting.md](troubleshooting.md)). |
| Ollama models       | Downloaded into `/var/lib/ollama` at runtime; re-pull them. The account sync is a Tier 2 login — `ollama signin` again.                              |
| Docker data         | Images and volumes under `/var/lib/docker`; re-pull or rebuild what you need.                                                                         |
| Application state   | Browser profiles, credential stores, anything you signed into — the Tier 2/3 rule ([doc/secrets.md](secrets.md)) says none of it is declarative, so none of it comes back. Working trees under `~/code` are clones to re-clone. |

Each of these takes minutes once you know it is coming, and costs an evening
when it is a surprise. Listing them is the whole point.

---

- VM install path: [doc/install-vm.md](install-vm.md)
- hplaptop delta: [doc/bare-metal-hplaptop.md](bare-metal-hplaptop.md)
- Rebuild aliases: [doc/workflow.md](workflow.md)
