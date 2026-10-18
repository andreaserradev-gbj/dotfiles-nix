# niri + Noctalia on geekom

geekom offers **two sessions at the GDM login screen**: GNOME, unchanged, and
niri with the [Noctalia](https://noctalia.dev) shell. Nothing is replaced, so
switching is a session choice, not a rebuild.

| session | started by | shell |
| ------- | ---------- | ----- |
| GNOME (default) | `gnome-session` | GNOME Shell + PaperWM + Catppuccin |
| Niri | `niri-session` → `niri.service` → `spawn-at-startup "noctalia"` | Noctalia |

## What owns what

- **System** (`hosts/geekom/default.nix`): `programs.niri.enable`, plus
  `pkgs.noctalia` and `pkgs.xwayland-satellite` in `environment.systemPackages`.
  The nixpkgs module adds the session package, the `niri.service` user unit,
  `xdg.portal.config.niri`, a PAM entry for `swaylock` and an XDG-autostart
  target. It changes nothing in the GNOME session.
- **Home** (`modules/home/niri.nix`): the two config files, gated on
  `osConfig.programs.niri.enable` so hplaptop never sees them.
- **Assets**: `config/niri/config.kdl` and `config/noctalia/config.toml`,
  copied verbatim (edit the file, there is no generator).

## Switching sessions

- **Into niri**: at GDM, pick *Niri* in the session menu (the gear, bottom
  right). `defaultSession` is unset, so the picker still preselects GNOME.
- **Back to GNOME**: *Noctalia* → session panel → *Log out*, `Mod+Shift+E`, or
  `niri msg action quit`. All three end the niri session and return to GDM,
  where GNOME is the entry you started from. GNOME keeps no state from niri, so
  the next login is the same desktop as before.
- **Recovery**: if a niri session will not start, `Ctrl+Alt+F3` to a TTY, log
  in, and `sudo nixos-rebuild switch --rollback`. GDM is outside the session, so
  a broken compositor cannot lock you out of the machine.

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
  polkit agent that GNOME's setup does not need.

Revisit when nixos-26.05 carries 5.3.x.

## What Noctalia replaces in that session

Bar, dock, launcher, control center, notifications, OSDs, wallpaper, lock
screen and session panel, from one binary. Verified as niri layer surfaces
(`noctalia-bar-default`, `noctalia-panel`, `noctalia-wallpaper`), with
`workspace-switch` moving between workspaces and `session lock` engaging
`ext_session_lock_v1`.

It authenticates the lock screen through PAM's `login` service, which is the
same stack `pam_gnome_keyring` already unlocks the login keyring from. Its
polkit prompt is its own (`polkit_agent = true`), because GNOME's agent lives
inside gnome-shell and is not running in a niri session.

## Gotchas

- **Noctalia's settings UI wins over the declarative config.** It writes
  `~/.local/state/noctalia/settings.toml`, merged after `config/noctalia/`.
  When a Nix setting appears ignored, inspect or delete that file.
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
