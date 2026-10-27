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

- **noctalia-greeter, hand-wired, unstable**: the greeter runs from
  `unstablePkgs.noctalia-greeter` (the channel's 1.3.1 ignores
  `[appearance.wallpaper]` on builtin schemes; 1.6.0 applies it — see the
  version note in `hosts/geekom/greeter.nix`), but the unstable NixOS module
  (`services.displayManager.noctalia-greeter`) is not adopted,
  so `hosts/geekom/greeter.nix` assigns the greetd command and delivers
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
- **Greeter theming is split: wallpaper declarative, palette/font by session
  sync**: greeter.toml wins over sync.toml on any key it sets, so the
  wallpaper is Nix-owned — a tmpfiles `r`+`C` copy stages
  `~/Pictures/Wallpapers/…` into `/var/lib/noctalia-greeter/wallpaper.jpg`
  on every boot, because the greeter account cannot read the user's 0700
  home. Palette and font still come from the session (`pkexec
  noctalia-greeter-apply-appearance`, polkit action from the package, admin
  = wheel) writing `/var/lib/noctalia-greeter/sync.toml`; sync.toml must
  never be written by hand.

## What owns what

- **Session** (`features/niri/nixos.nix`, imported by name from
  `hosts/geekom/default.nix`): `programs.niri.enable` plus the session's
  packages in `environment.systemPackages`. The nixpkgs module adds the
  session package, the `niri.service` user unit, `xdg.portal.config.niri`
  (gnome+gtk — niri implements Mutter's ScreenCast API, so no portal-wlr), a
  PAM entry for `swaylock` and an XDG-autostart target. The same feature
  carries the explicit-enable assertions the GNOME defaults used to hide:
  ibus off, dconf on, gnome-keyring on, and the niri package override that
  installs the fixed session script (see the gotchas).
- **Greeter** (`hosts/geekom/greeter.nix`): greetd + noctalia-greeter, the
  greetd command, the AccountsService daemon, and the tmpfiles-delivered
  `greeter.toml`. Host-local by import, like `usb-mouse-recovery.nix` —
  hplaptop keeps GDM and never evaluates it.
- **Home** (`features/niri/home.nix`): the session's two config files, gated on
  `osConfig.programs.niri.enable` so hplaptop never sees them. The niri
  config is validated with `osConfig.programs.niri.package` — the same build
  the system runs, so the closure holds one niri and not two.
- **Assets**: `config/niri/config.kdl`, `config/noctalia/config.toml` and
  `config/niri/niri-session`, copied verbatim (edit the file, there is no
  generator).

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

## Where Noctalia comes from

Two sources, deliberately split:

- **the shell** — `unstablePkgs.noctalia`, wired as a `nixpkgs.overlays` entry in
  [hosts/geekom/default.nix](../hosts/geekom/default.nix). The channel's 5.0.1
  stops at plugin API 30; unstable's 5.3.0 reaches 34, which is what the
  screen-toolkit plugin's `annotate` and the newer shell IPC need. An overlay,
  not a package substitution, because `pkgs.noctalia` has two consumers — the
  feature's `systemPackages` and the build-time `noctalia config validate` gate
  in [features/niri/home.nix](../features/niri/home.nix) — and `useGlobalPkgs`
  makes them share one `pkgs`. Measured cost of the swap on geekom: +149 store
  paths (560.8 MiB) added, 21 (66.6 MiB) removed, all of it substitution from
  `cache.nixos.org` — nothing is built. The marginal tree is the second
  pipewire/glib generation the two trees carry; it is what buys the version.
- **upstream's flake is still not used**, for the reasons that have not changed:
  without `follows` it pins a whole nixpkgs generation of its own, with
  `follows` it builds from source and misses its cache, and either way
  `disabledModules` replaces the nixpkgs module and adds a KDE polkit agent this
  session does not need.

`nfu` carries later versions with no edit: the overlay names a package, not a
version.

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
  build time** (`features/niri/home.nix`). niri falls back to defaults on a bad
  config and Noctalia ignores one it cannot parse, so without the gate a typo
  would only show up as a session with no bar.
- **`xwayland-satellite` is required.** The nixpkgs niri module passes
  `enableXWayland = false`; without the satellite on PATH, every X11 app is
  unavailable and niri logs `error spawning xwayland-satellite`.
- **Noctalia's niri theme integration cannot apply here.** It appends an
  `include` line to `~/.config/niri/config.kdl`, which is a read-only
  Home Manager symlink; keep niri colours hand-written.
- **The niri package carries a fixed session script.** niri 26.04's
  `niri-session` calls the blanket `systemctl --user import-environment`, and
  systemd 260 answers that with "Calling import-environment without a list of
  variable names is deprecated". The session script's stdout is the login VT,
  so the warning prints on screen during login. Upstream fixed it (niri
  `4adbf00`, not yet released), so the fixed script is carried as
  [config/niri/niri-session](../config/niri/niri-session) and the feature
  installs it over the packaged one.
- **The script is swapped AFTER the build, never patched into the source.**
  niri is a `buildRustPackage`: patching its tree changes the derivation
  hash, which rebuilds niri from source — measured at ~15 minutes of extra CI
  time per geekom build, for a change that touches no Rust code. Replacing
  one installed script leaves the cargo build untouched and
  cache-substitutable, so the whole system builds in seconds. The override
  is a `symlinkJoin` with a `postBuild` that copies the script and re-patches
  its shebang.
- **The guard is what makes the override self-deleting.** The `postBuild`
  fails the build if the packaged script no longer contains the blanket
  call — that is the signal that upstream shipped the fix, and both the
  override and `config/niri/niri-session` should be deleted. Without the
  guard the override would silently keep shadowing a script that no longer
  needs fixing.
