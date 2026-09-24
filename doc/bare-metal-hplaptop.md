# Installing on bare metal — hplaptop

The geekom walkthrough ([doc/bare-metal-geekom.md](bare-metal-geekom.md)) covers
a generic bare-metal install in detail. This document is the **delta** for the HP
laptop — what differs, not what is the same. The HP laptop is a vanilla install
with no GPU traps, so it is shorter; the one caveat that is real here is
**suspend** (verified working and unmasked — see below).

The host is for a non-technical user (Elisa). The design constraints follow
from that:

- **No dev tooling, no sshd.** `local.dev.enable = false` in
  `hosts/hplaptop/default.nix` (explicit). The `dev.nix` seam gates nix-ld,
  ollama, opencode, nodejs, uv, jq, python3, **and** sshd + authorized_keys —
  all off.
- **Vanilla GNOME**, not PaperWM + Catppuccin. `local.desktop.variant =
  "vanilla"` skips the HM theming modules (see the desktop module's callout).
- **LibreOffice enabled** (`local.desktop.libreoffice.enable = true`) — Elisa
  needs Word/Excel for HR work.
- **Bash shell, not zsh.** `users.users.elisa.shell = lib.mkForce pkgs.bash`
  overrides `common.nix`'s bare `pkgs.zsh` — priority 50 beats the bare
  assignment's 100, and lower wins.
- **Email in Brave, not Thunderbird.** Elisa's email is configured directly in
  Brave with her Google account. There is no `email` field in her `user.nix`
  entry and no `modules/home/mail.nix`.
- **Wi-Fi powersave on.** `networking.networkmanager.wifi.powersave =
  lib.mkForce true` — a laptop trades a little latency for battery life, the
  opposite tradeoff from the mains-powered geekom box.
- **No `sshKey` in `user.nix`.** sshd is off, so nothing consumes it. Andrea
  maintains this box on-site; Elisa updates via `nrb` (see
  [doc/workflow.md](workflow.md)).

## Before you wipe

Record the Windows licence key from the ACPI MSDM table (see the geekom
walkthrough, step 0). Read the BIOS/EC versions. The HP laptop's firmware is not
the geekom firmware — do not assume the same quirks, but the same cautions apply.

## Firmware

Default to not flashing (same reasoning as geekom). If you do flash, disable
Secure Boot _after_, not before.

## Install

The install is the same four-phase `bootstrap.sh` flow as geekom:

```sh
curl -fsSL https://raw.githubusercontent.com/andreaserradev-gbj/dotfiles-nix/main/bootstrap.sh \
  | sudo bash -s -- hplaptop
```

Two things must be done first, both before booting the ISO:

1. **Confirm the disk device** in `hosts/hplaptop/disk-config.nix`. On this
   repo's own machine it is already filled in with a real by-id node. On any
   OTHER machine, replace it with that box's node from
   `ls -l /dev/disk/by-id/`, then commit and push — `bootstrap.sh` fetches the
   layout from GitHub, and refuses to run against a path containing
   `PLACEHOLDER`.
2. **Confirm the initrd modules** in
   `hosts/hplaptop/hardware-configuration.nix` — also already filled in for this
   box. On any OTHER machine, run
   `nixos-generate-config --no-filesystems --dir /tmp/cfg` on the booted ISO
   and copy the `boot.initrd.availableKernelModules` list into the committed
   file. An EMPTY list will not boot on real hardware — the committed one is
   this ProBook's, so re-capture rather than reuse it elsewhere.
   `boot.kernelModules = [ "kvm-intel" ]` is already set (this is an Intel box,
   not AMD).

The by-label mounts (`/` → `hplaptop`, `/boot` → `BOOT`) are hand-written and
must match the labels `disk-config.nix` creates. disko and the committed
hardware config agree by construction; verify rather than re-derive.

> **Intel, not AMD.** `hardware.cpu.intel.updateMicrocode = true` (not
> `hardware.cpu.amd`), and there is no `hardware.amdgpu.initrd.enable`. The
> HP laptop has an Intel i5 with integrated graphics — no discrete GPU, no
> AMD-specific firmware.

## After first boot

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
from the geekom walkthrough applies here too — change the password before
launching a browser, or re-key the keyring in seahorse afterwards.

**Elisa's email.** Configure her Google account directly in Brave — there is
no Thunderbird on this host and no `email` field in her `user.nix` entry.

## Suspend — verified working, unmasked

`hosts/hplaptop/default.nix` sets **no `systemd.targets` mask**: suspend and
resume are verified working on this hardware (`verified 2026-08-27`) —
`systemctl suspend`, wake via the power button, a clean suspend/resume cycle in
the journal, with desktop and network recovering.

**If resume ever regresses** — e.g. after a firmware update — add this block to
`hosts/hplaptop/default.nix`, rebuild, and commit:

```nix
systemd.targets = {
  sleep.enable = false;
  suspend.enable = false;
  hibernate.enable = false;
  hybrid-sleep.enable = false;
};
```

The full reasoning lives in `hosts/geekom/default.nix` (the `systemd.targets`
block), which keeps its mask permanently: that machine has no S3 state and
hangs hard mid-suspend. The firmware advertising S-states is not evidence that
resume works.

> **A mask covers GDM's greeter too; unmasked, the greeter does not.** GNOME
> Settings → Power → Automatic Suspend writes to the logged-in user's dconf,
> but GDM's greeter runs as its own user with its own idle timer, so a box left
> sitting at the login screen suspends itself. With suspend unmasked here that
> timer is live: if it ever hangs the box, re-mask rather than debugging dconf.

## Updating the system

Elisa has no local clone of this repo and no `nh`. Her updates go through two
bash aliases, `nrb` and `ngca`, defined in `modules/home/maintenance.nix`
(gated on `!osConfig.local.dev.enable`, so they appear only on non-dev hosts;
the `nh`-backed aliases in `modules/home/shell.nix` sit behind the matching dev
gate and are absent here):

```sh
nrb    # sudo nixos-rebuild boot --flake github:andreaserradev-gbj/dotfiles-nix/verified --refresh
ngca   # sudo nix-collect-garbage --delete-older-than 14d, then prune the boot menu
```

`boot` (not `switch`) so a kernel or display-stack change does not tear down
the running session — a reboot applies it. Andrea runs a full `nixos-rebuild`
on on-site visits; Elisa runs `nrb` and reboots.

**The ref is `verified`, not `main`.** CI fast-forwards `verified` only after
the build matrix passes, so this machine cannot fetch a commit that has not
built. See [doc/workflow.md](workflow.md) for the pipeline.

`ngca` keeps a **14-day** rollback window rather than deleting every old
generation: on this machine the boot menu is the only recovery path, and `-d`
would leave only the running generation to boot from. It also prunes the boot
menu through
`/nix/var/nix/profiles/system/bin/switch-to-configuration` — the profile, not
the running system. Running it against the running system after an `nrb` would
rewrite the bootloader with the *old* system as default, silently discarding
the staged update; `nrb`-then-reboot is exactly this host's workflow, so that
mattered here more than anywhere.

> **No SSH on this host.** sshd is gated behind `local.dev.enable`, which is
> false here. There is no network rebuild path and no authorized_keys entry.
> Maintenance is either `nrb` (Elisa) or on-site (Andrea).

## What a reinstall does not restore

Same shape as geekom's list — wifi password, Bluetooth pairings and the rest of
the application state — plus LibreOffice's own documents and recent-files
state, which only this host installs. None of it is in this repo. (There is no
GitHub key to re-add: this host has no clone.) See the table at the end of
[doc/bare-metal-geekom.md](bare-metal-geekom.md).

---

- Full generic walkthrough: [doc/bare-metal-geekom.md](bare-metal-geekom.md)
- VM install path: [doc/install-vm.md](install-vm.md)
