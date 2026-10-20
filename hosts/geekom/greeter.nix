# The only path in: greetd + noctalia-greeter on VT1. Lives with this host like
# usb-mouse-recovery.nix — hplaptop keeps GDM and must not see greetd. The
# session option that dropped GDM lives in modules/nixos/desktop.nix.
#
# noctalia-greeter bundles its own compositor, so this file is hand-wired: the
# NixOS module is missing from the pinned channel (it exists in unstable,
# nixos/modules/services/display-managers/noctalia-greeter.nix) and greeter.toml
# is delivered the same way that module does it — a systemd.tmpfiles symlink,
# not a file copy — so /var/lib/noctalia-greeter keeps working exactly like an
# upstream install: greeter.toml declarative (Nix-owned), sync.toml written by
# the appearance sync from the session (polkit action
# org.noctalia.greeter.apply-appearance ships with the package; admin = wheel).
#
# The greeter's theme default is declarative in greeter.toml below
# ([appearance]); Sync's runtime keys (palette, font) layer on top in
# sync.toml. The wallpaper, though, must live in the greeter's own directory:
# per upstream docs the [appearance.wallpaper] path is read by the `greeter`
# account, which cannot see the user's 0700 home — a Nix-run tmpfiles copy
# stages it (same model as Sync's own `wallpaper*` staging, but declarative).
# regreet was removed with the theme trial (static-image polish was tried
# first and rejected on the real panel).
{
  lib,
  pkgs,
  unstablePkgs,
  user,
  ...
}:

{
  services.greetd.enable = true;

  # Boot and handoff polish for the graphical path: without a splash, the
  # kernel/systemd console text sits in the tty1 buffer and shows through for
  # ~1 s between the greeter exiting and niri's first frame (greetd owns
  # vt 1, nothing repaints until the session shell uploads the wallpaper).
  # `quiet` stops systemd's status lines and loglevel 3 keeps kernel
  # err-level lines (amdgpu display-init REG_WAIT spam) out of that buffer,
  # so the handoff shows a plain black beat instead of unreadable text; both
  # streams remain in the journal. greetd's unit already orders itself
  # After=plymouth-quit-wait.service, so the splash ends exactly when the
  # greeter takes the display.
  boot.plymouth.enable = true;
  boot.kernelParams = [ "quiet" ];
  boot.consoleLogLevel = 3;

  # Password auth — a daily workstation with sops secrets and SSH keys on
  # disk, not a kiosk (the VM's greetd uses `nullok` for exactly that
  # reason). No `initial_session`: nothing autologins.
  # The greeter runs from nixos-unstable — see the version note below.
  services.greetd.settings.default_session.command = "${lib.getExe unstablePkgs.noctalia-greeter}";

  # The greeter user list comes from AccountsService (D-Bus), which regreet's
  # module used to enable implicitly — now explicit. accountsservice on the
  # system bus confirmed by services.dbus.packages.
  services.accounts-daemon.enable = true;

  # The greeter is the UNSTABLE package, not the channel's 1.3.1: 1.3.1 only
  # applies [appearance.wallpaper] under the Synced scheme with a complete
  # 16-key palette, and clears it for builtin schemes — 1.6.0 dropped both
  # restrictions (upstream docs: wallpaper works with builtins like
  # Catppuccin). Host-local reference — the flake guard rule allows
  # `unstablePkgs` from hosts/geekom/. Keyboard: the session reads its layout
  # from systemd-localed (modules/nixos/desktop.nix sets it from
  # user.keyboardLayout = "it"); this compositor reads ITS OWN keymap from
  # greeter.toml and would fall back to "us" — so "it" here is not cosmetic,
  # it is the IT password keys. numlock matches config/niri/config.kdl.
  # `r`+`C` re-stage the wallpaper on every boot (tmpfiles-setup runs with
  # --create --remove, so `C` alone would never overwrite): the file is
  # user-managed — same path config/noctalia/config.toml points the session
  # at — and a copy is the only form the greeter account can read.
  environment.etc."tmpfiles.d/10-noctalia-greeter.conf".text = ''
    d     /var/lib/noctalia-greeter                       0750 greeter greeter - -
    r     /var/lib/noctalia-greeter/wallpaper-declarative.jpg  -    -       -       - -
    C     /var/lib/noctalia-greeter/wallpaper-declarative.jpg  0644 greeter greeter - ${user.homeDirectory}/Pictures/Wallpapers/3d-render-bloom-3840x2160-27150.jpg
    L+    /var/lib/noctalia-greeter/greeter.toml          -    -       -       - ${pkgs.writeText "noctalia-greeter-greeter.toml" ''
      # declarative; UI and Sync never write this — sync.toml holds runtime keys
      [keyboard]
      layout = "it"
      numlock = true
      # Builtin Catppuccin theme + declarative wallpaper; the absolute path
      # points at the staged copy from the `C` rule above — never the user's
      # home, which the greeter account cannot read (0700).
      [appearance]
      scheme = "Catppuccin"
      theme_mode = "dark"
      [appearance.wallpaper]
      path = "/var/lib/noctalia-greeter/wallpaper-declarative.jpg"
      fill_mode = "crop"
      [output]
      # Same panel and scale as the user session, so the handoff does not
      # rescale the display (DP-6 4K at 1.25, as greeter.kdl did).
      name = "DP-6"
      scale = 1.25
    ''}
  '';
}
