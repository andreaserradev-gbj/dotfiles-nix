# niri + Noctalia on geekom

geekom runs **one session**: [niri](https://github.com/YaLTeR/niri) with the
[Noctalia](https://noctalia.dev) shell. There is no session chooser and no
fallback desktop — GDM and GNOME are not installed — so changing the session
is a rebuild, not a login-screen choice.

## The path in: greetd → noctalia-greeter

```
power → systemd → greetd (VT1)
                   └─ noctalia-greeter-session (bundled compositor + greeter)
                        └─ password auth → niri-session + Noctalia
```

- **noctalia-greeter, hand-wired**: the package is in the pinned channel
  (1.3.1) but its NixOS module is not (it exists in unstable), so
  `hosts/geekom/greeter.nix` assigns the greetd command and delivers
  `greeter.toml` through a systemd tmpfiles symlink — the same pattern the
  unstable module uses. The greeter bundles its own compositor, so the
  `niri validate` gate covers the session configs only, not the greeter.
- **Password auth, no autologin**: a daily workstation with sops secrets and
  SSH keys on disk. The VM's kiosk (`nullok`, no prompt) is the deliberate
  contrast — [doc/vm-console.md](vm-console.md). The keyring unlock chains are
  unchanged: greetd's PAM service wires `enableGnomeKeyring`, and Noctalia's
  lock screen authenticates through PAM's `login` service.
- **Keyboard layout is declared, not inherited**: the session's niri reads
  its layout from systemd-localed (`user.keyboardLayout`), but the greeter
  compositor reads its own `[keyboard]` from `greeter.toml` and would fall
  back to `us`. `greeter.toml` sets `layout = "it"` from the same
  `user.nix` field — change one, check the other.
- **The greeter is themed by the session, not by Nix**: from the running
  Noctalia session, appearance sync (`pkexec noctalia-greeter-apply-appearance`,
  polkit action from the package, admin = wheel) writes wallpaper, palette and
  font into `/var/lib/noctalia-greeter/sync.toml`; it applies on the next
  login screen. `greeter.toml` is the Nix-owned declarative half (keyboard,
  output scale); sync.toml must never be written by hand.

## What owns what

- **Session** (`hosts/geekom/default.nix`): `programs.niri.enable` plus
  `pkgs.noctalia` and `pkgs.xwayland-satellite` in
  `environment.systemPackages`. The nixpkgs module adds the session package,
  the `niri.service` user unit, `xdg.portal.config.niri` (gnome+gtk — niri
  implements Mutter's ScreenCast API, so no portal-wlr), a PAM entry for
  `swaylock` and an XDG-autostart target. The same host file carries the
  explicit-enable assertions the GNOME defaults used to hide: ibus off, dconf
  on, gnome-keyring on.
- **Greeter** (`hosts/geekom/greeter.nix`): greetd + noctalia-greeter, the
  greetd command, the AccountsService daemon, and the tmpfiles-delivered
  `greeter.toml`. Host-local by import, like `usb-mouse-recovery.nix` —
  hplaptop keeps GDM and never evaluates it.
- **Home** (`modules/home/niri.nix`): the session's two config files, gated on
  `osConfig.programs.niri.enable` so hplaptop never sees them.
- **Assets**: `config/niri/config.kdl` and `config/noctalia/config.toml`,
  copied verbatim (edit the file, there is no generator).

## Recovery

Recovery is generation-level, not session-level — there is no second session
to fall back to:

- **TTY**: `Ctrl+Alt+F3`, log in, `sudo nixos-rebuild switch --rollback`.
- **Boot menu**: the previous generations are selectable at boot; one boots
  the old system without touching the current profile.
- **SSH**: `local.loopbackRebuild` keeps rebuilds outside the display stack
  entirely, so a dead session never blocks a repair
  ([doc/workflow.md](workflow.md)).

A broken compositor cannot lock you out: greetd sits outside the session and
respawns — `Mod+Shift+E` ends niri and lands back at the greeter.

`systemctl suspend` returns access denied on this host: `sleep.target` and
`suspend.target` are masked (`hosts/geekom/default.nix`), which is why
`config/noctalia/config.toml` declares the session panel without *Lock &
Suspend*.

## Why niri and not sway or Hyprland

Measured marginal cost against the running geekom system, and moves outside the
compositor:

| candidate | new paths | marginal | other moves |
| --------- | --------- | -------- | ----------- |
| niri 26.04 | 2 | 37.5 MiB | seatd, `niri-portals.conf` |
| sway 1.12 | 15 | 10.8 MiB | 10 packages (foot, waybar, wmenu, swayidle, swaylock, pulseaudio, grim, brightnessctl, xwayland, portal-wlr) |
| hyprland 0.55.4 | 28 | 271.0 MiB | portal-hyprland, a setuid wrapper, xwayland |

Sway is cheaper in bytes but installs its own terminal, bar, launcher and
locker. Hyprland is seven times niri's footprint. Niri adds the compositor and
nothing else, which is what makes Noctalia viable: the shell owns every surface,
so a second bar and launcher would be duplication.

## Why Noctalia comes from nixpkgs

Your pinned nixpkgs carries `noctalia-5.0.1`, which accepts every key the
config uses. Upstream's flake is 5.3.0 and pins its own nixpkgs:

- without `follows`, a second glibc, pipewire, gcc and systemd generation,
  805 MiB marginal over this system;
- with `follows`, a from-source build (~5 min here) that misses its own cache;
- either way, `disabledModules` replaces the nixpkgs module and adds a KDE
  polkit agent that this setup does not need.

Revisit when nixos-26.05 carries 5.3.x.

## What Noctalia replaces

Bar, dock, launcher, control center, notifications, OSDs, wallpaper, lock
screen and session panel, from one binary. Verified as niri layer surfaces
(`noctalia-bar-default`, `noctalia-panel`, `noctalia-wallpaper`), with
`workspace-switch` moving between workspaces and `session lock` engaging
`ext_session_lock_v1`.

Its polkit prompt is its own (`polkit_agent = true`): GNOME's agent lived
inside gnome-shell, which is gone, so Noctalia is the only polkit agent in the
session.

## Gotchas

- **Noctalia's settings UI wins over the declarative config.** It writes
  `~/.local/state/noctalia/settings.toml`, merged after `config/noctalia/`.
  When a Nix setting appears ignored, inspect or delete that file — this
  includes the lock screen's login-box widget settings, which the state file
  owns.
- **niri's own default config is never merged.** A config file exists, so the
  built-in one is not used at all; every bind in `config/niri/config.kdl` is
  deliberate. Diff it against upstream's `default-config.kdl` at the pinned tag
  when nixpkgs moves.
- **`config/niri/config.kdl` and `config/noctalia/config.toml` are validated at
  build time** (`modules/home/niri.nix`). niri falls back to defaults on a bad
  config and Noctalia ignores one it cannot parse, so without the gate a typo
  would only show up as a session with no bar.
- **`xwayland-satellite` is required.** The nixpkgs niri module passes
  `enableXWayland = false`; without the satellite on PATH, every X11 app is
  unavailable and niri logs `error spawning xwayland-satellite`.
- **Noctalia's niri theme integration cannot apply here.** It appends an
  `include` line to `~/.config/niri/config.kdl`, which is a read-only
  Home Manager symlink; keep niri colours hand-written.
