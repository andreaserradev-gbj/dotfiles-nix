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
  ollama, opencode, nodejs, uv, jq, **and** sshd + authorized_keys — all off.
- **Vanilla GNOME**, not PaperWM + Catppuccin. `local.desktop.variant =
  "vanilla"` skips the HM theming modules (see the desktop module's callout).
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
no Thunderbird on this host and no `email` field in `user.nix`.

## Suspend — verified working, unmasked

Suspend was **masked by default** on this host until it could be verified
on-site — the geekom box proved that "the firmware advertises S-states" is not
evidence that resume works. That verification happened on **2026-08-27**
(Andrea on-site): `systemctl suspend` → wake via power button → a clean
suspend/resume cycle in the journal, with desktop and network recovering. The
`systemd.targets` mask block was removed after that test
(commit `4f7a6cc`).

The historical mask was:

```nix
systemd.targets = {
  sleep.enable = false;
  suspend.enable = false;
  hibernate.enable = false;
  hybrid-sleep.enable = false;
};
```

**If resume ever regresses** — e.g. after a firmware update — restore that
block in `hosts/hplaptop/default.nix`, rebuild, and commit. The full reasoning
lives in `hosts/geekom/default.nix` (the `systemd.targets` block), which keeps
its mask permanently: that machine has no S3 state and hangs hard mid-suspend.

> **A mask covers GDM's greeter too; unmasked, the greeter does not.** GNOME
> Settings → Power → Automatic Suspend writes to the logged-in user's dconf,
> but GDM's greeter runs as its own user with its own 900s idle timer — that
> is exactly how the geekom box was lost (nobody logged in, greeter suspended
> 15 minutes after boot). With suspend unmasked here, the greeter timer is
> live: if it ever hangs the box, re-mask rather than debugging dconf.

## Updating the system

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

## What a reinstall does not restore

Same set as geekom — wifi password, Bluetooth pairings, browser profiles,
LibreOffice state. All live outside this repo. See the table at the end of
[doc/bare-metal-geekom.md](bare-metal-geekom.md).

---

- Full generic walkthrough: [doc/bare-metal-geekom.md](bare-metal-geekom.md)
- VM install path: [doc/install-vm.md](install-vm.md)
