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
# ([appearance]); the sync layers runtime keys on top (wallpaper, palette,
# font) — the wallpaper must be a staged COPY in the greeter's own directory,
# because the greeter account cannot read the user's 0700 home. Judged and
# accepted at the trial boot; regreet was removed with it
# (static-image polish was tried first and rejected on the real panel).
{
  lib,
  pkgs,
  ...
}:

{
  services.greetd.enable = true;

  # Password auth — a daily workstation with sops secrets and SSH keys on
  # disk, not a kiosk (the VM's greetd uses `nullok` for exactly that
  # reason). No `initial_session`: nothing autologins.
  services.greetd.settings.default_session.command = "${lib.getExe pkgs.noctalia-greeter}";

  # The greeter user list comes from AccountsService (D-Bus), which regreet's
  # module used to enable implicitly — now explicit. accountsservice on the
  # system bus confirmed by services.dbus.packages.
  services.accounts-daemon.enable = true;

  # greeter.toml keys verified against the binary's embedded template
  # (noctalia-greeter 1.3.1). Layout: the session reads its layout from
  # systemd-localed (modules/nixos/desktop.nix sets it from
  # user.keyboardLayout = "it"); this compositor reads ITS OWN keymap from
  # greeter.toml and would fall back to "us" — so "it" here is not cosmetic,
  # it is the IT password keys. numlock matches config/niri/config.kdl.
  environment.etc."tmpfiles.d/10-noctalia-greeter.conf".text = ''
    d     /var/lib/noctalia-greeter                       0750 greeter greeter - -
    L+    /var/lib/noctalia-greeter/greeter.toml          -    -       -       - ${pkgs.writeText "noctalia-greeter-greeter.toml" ''
      # declarative; UI and Sync never write this — sync.toml holds runtime keys
      [keyboard]
      layout = "it"
      numlock = true
      # Theme default; Sync's staged wallpaper copy and runtime keys land in
      # sync.toml on top of this.
      [appearance]
      scheme = "Catppuccin"
      theme_mode = "dark"
      [output]
      # Same panel and scale as the user session, so the handoff does not
      # rescale the display (DP-6 4K at 1.25, as greeter.kdl did).
      name = "DP-6"
      scale = 1.25
    ''}
  '';
}
