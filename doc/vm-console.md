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

## Fallback

`Ctrl+Alt+F2` reaches a bare kernel tty at all times (cage keeps VT-switching via
its `-s` flag); `Ctrl+Alt+F1` returns to foot. The tty is the true escape hatch, so
cage never has to be bulletproof. SSH is independent of the console entirely — a
broken compositor cannot lock you out: `ssh` in and roll back a generation.

## Development stays on the Mac

The GUI-in-VM is _only_ the terminal. Editing, the browser, and the dev loop stay
on the Mac over SSH. To reach a dev server running inside the VM:

```sh
ssh -L 5173:[::1]:5173 nixos     # forward the VM port to the Mac
```

or bind the server to `0.0.0.0`, open the firewall port, and hit the VM's IP.
(For why the forward target is the v6 loopback, see the Vite note in
[doc/dev-environments.md](dev-environments.md).)

## Known limitations

- **Clipboard is not wired.** `spice-vdagentd` runs, but the session-side
  `spice-vdagent` client that would sync the clipboard is never started (a bare
  cage kiosk has nothing to autostart it). This is intentional for an insurance
  console — use SSH for anything that needs the Mac clipboard. To enable it, have
  cage launch a small wrapper that starts `spice-vdagent` before `exec`-ing foot.
- **Console resolution is set host-side, not in this repo.** cage (wlroots)
  always uses the mode the host advertises as _preferred_ — `1280x800` unless
  told otherwise. The fix is the pair of `-global virtio-gpu-pci.xres/yres`
  QEMU arguments from the UTM setup step
  ([doc/install-vm.md](install-vm.md)); a one-time UTM setting that cannot be
  made declarative here. Guest-side levers do NOT work, don't re-attempt them:
  `video=Virtual-1:…` in `boot.kernelParams` only sizes the pre-cage _text_
  console; cage ignores `wlr-randr` mode/scale requests and has no output-scale
  knob; forcing an EDID via `drm.edid_firmware` empties the virtio-gpu mode
  list and kills the display outright ("Display output is not active" — SSH
  still works, revert and reboot to recover). Text size lives in
  `modules/home/foot.nix` (`font = …:size=`).

---

- VM install walkthrough: [doc/install-vm.md](install-vm.md)
- Rebuild aliases and rollback: [doc/workflow.md](workflow.md)
