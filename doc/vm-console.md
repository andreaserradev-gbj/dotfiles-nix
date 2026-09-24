# Local console (cage + foot) — the VM only

The UTM window boots straight into a full-screen [foot](https://codeberg.org/dnkl/foot)
terminal — autologin, no display manager — via [cage](https://github.com/cage-kiosk/cage),
a single-app kiosk Wayland compositor. This is a _local_ console for when SSH or
networking is down (or during a bad rebuild), **not** a second workspace: the real
dev loop stays SSH-from-the-Mac. Everything is software-rendered — the
VM has no usable GPU.

Two layers, one rebuild:

- **System** (`hosts/vm/default.nix`) — `services.cage` (compositor + autologin),
  `services.spice-vdagentd`, and the `video=` display mode.
- **Home** (`modules/home/foot.nix`, `modules/home/fonts.nix`,
  `modules/home/starship.nix`) — the terminal, its fonts, and the prompt.

## Why these pieces

- **cage, not a desktop.** cage shows exactly one full-screen program and _is_ the
  login: its systemd unit (`cage-tty1`) conflicts with `getty@tty1` and logs the
  user in through the PAM service `cage`, whose `unix` auth rule is `nullok` — no
  login prompt. No display manager runs on this host either — `local.desktop.enable`
  is off, so the desktop seam's GDM never gets enabled.
- **foot, not kitty/alacritty.** foot rasterizes glyphs purely on the CPU — no
  OpenGL/EGL — so it's the one terminal that works on a GPU-less guest. GL-based
  terminals may not even start under software rendering.
- **`WLR_RENDERER = "pixman"` (mandatory).** Forces wlroots' pure-CPU renderer.
  `WLR_RENDERER_ALLOW_SOFTWARE=1` (GLES2-on-llvmpipe) is _not_ enough here — EGL
  can't initialize on this guest; pixman bypasses GL entirely. Paired with
  `WLR_NO_HARDWARE_CURSORS=1`, which fixes the cursor rendering at the wrong offset.
- **The Nerd Font is load-bearing.** foot rasterizes glyphs via fontconfig (the
  kernel tty can't), so a correct monospace font is the whole point of a local
  terminal. A small `DejaVu Sans` fallback covers the Unicode glyphs JetBrainsMono
  Nerd Font lacks (e.g. `⇡` in the git prompt), and starship's read-only marker is
  its default 🔒 emoji — covered by the color-emoji font `modules/home/fonts.nix`
  installs and registers as fontconfig's `emoji` default.
- **`WorkingDirectory = user.homeDirectory`.** cage's unit otherwise defaults to
  `/`, so the console would open in the root filesystem. Set on the `cage-tty1`
  service.

## Fallback

`Ctrl+Alt+F2` reaches a bare kernel tty at all times (cage keeps VT-switching via
its `-s` flag); `Ctrl+Alt+F1` returns to foot. The tty is the true escape hatch, so
cage never has to be bulletproof. SSH is independent of the console entirely — a
broken compositor cannot lock you out: `ssh` in and roll the system profile back a
generation with `sudo nixos-rebuild switch --rollback`.

## Development stays on the Mac

The GUI-in-VM is _only_ the terminal; editing, the browser and the dev loop stay on
the Mac. Reaching a dev server inside the VM is the ordinary SSH port forward —
[doc/dev-environments.md](dev-environments.md).

## Known limitations

- **Clipboard is not wired.** `services.spice-vdagentd` starts the daemon, but the
  session-side `spice-vdagent` client that would sync the clipboard is never
  started: a bare cage kiosk runs no session autostart, and the package's XDG
  autostart entry is what normally launches it (its `spice-vdagent.desktop` needs
  a desktop session). It is the X11 build of the agent, so it wants to talk to an
  X display — which cage's Xwayland does provide. This is intentional for an
  insurance console — use SSH for anything that needs the Mac clipboard.
- **Console resolution is set host-side, not in this repo.** cage (wlroots) uses
  the mode the host advertises as _preferred_ — QEMU's virtio-gpu defaults to
  `1280x800` unless told otherwise. The fix is the pair of
  `-global virtio-gpu-pci.xres/yres` QEMU arguments from the UTM setup step
  ([doc/install-vm.md](install-vm.md)); a one-time UTM setting that cannot be
  made declarative here. Guest-side levers do NOT pin the kiosk, don't re-attempt
  them: `video=Virtual-1:…` in `boot.kernelParams` only sizes the pre-cage _text_
  console; `wlr-randr` can reach cage (it does implement `wlr-output-management`)
  but only to pick another mode the host already advertises, and cage re-picks the
  preferred mode on every start; forcing an EDID via `drm.edid_firmware` breaks the
  display outright instead ("Display output is not active" — SSH still works,
  revert and reboot to recover). Text size lives in
  `modules/home/foot.nix` (`font = …:size=`).

---

- VM install walkthrough: [doc/install-vm.md](install-vm.md)
- Rebuild aliases and daily commands: [doc/workflow.md](workflow.md)
