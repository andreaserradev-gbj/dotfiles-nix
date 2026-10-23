# The niri session's NixOS half: the compositor, its packages and the services
# GNOME used to provide. Not a seam — there is no `local.*` option here. A host
# that wants the session imports this feature BY NAME from the registry and
# sets `local.desktop.session = "niri"` itself: the setting stays with the host
# because it is the host's choice, not the feature's.
{
  pkgs,
  ...
}:
{
  # The channel's niri 26.04 still ships a niri-session that calls the
  # blanket `systemctl --user import-environment`; systemd 260 answers that
  # with "Calling import-environment without a list of variable names is
  # deprecated", and niri-session runs with its stdout on the login VT, so
  # the warning prints on screen during login. Upstream fixed it (niri
  # 4adbf00) but no release carries it yet, so the fixed script is carried
  # in config/niri/niri-session and installed OVER the packaged one.
  #
  # Installed after the build, not patched into the source: niri is a
  # buildRustPackage, so patching its tree would invalidate the cargo build
  # and rebuild niri from source on every CI run (~15 min). Replacing one
  # installed script leaves the Rust build untouched and cache-substitutable
  # (the join builds in seconds).
  #
  # The guard fails the build once the packaged script no longer has the
  # blanket call — that is the signal that upstream shipped the fix, and this
  # override and config/niri/niri-session should both be deleted.
  programs.niri.enable = true;
  programs.niri.package =
    (pkgs.symlinkJoin {
      name = "niri-session-fixed";
      paths = [ pkgs.niri ];
      postBuild = ''
        if ! grep -q "systemctl --user import-environment" $out/bin/niri-session; then
          echo "!! the packaged niri-session no longer has the blanket import:" >&2
          echo "!! upstream shipped the fix — delete this override and" >&2
          echo "!! config/niri/niri-session." >&2
          exit 1
        fi
        rm -f $out/bin/niri-session
        cp ${../../config/niri/niri-session} $out/bin/niri-session
        chmod +x $out/bin/niri-session
        patchShebangs $out/bin/niri-session
      '';
    }).overrideAttrs
      (_: {
        # The nixpkgs module puts this package in displayManager.sessionPackages,
        # which asserts the package carries `providedSessions`; symlinkJoin does
        # not inherit the passthru of the package it joins.
        passthru.providedSessions = pkgs.niri.providedSessions;
      });
  # Recording backend for Noctalia's screen_recorder plugin (config/noctalia/
  # config.toml): the module wraps gsr-kms-server with cap_sys_admin+ep, so
  # capture is promptless — the xdg-desktop-portal-gnome chooser this avoids
  # does not render under niri (xdg-desktop-portal#2039).
  programs.gpu-screen-recorder.enable = true;

  # Explicit-enable trio for the niri session, each currently a GNOME
  # `mkDefault` the greetd cutover would otherwise silently remove with GNOME:
  # ibus off kills the keyboard-notification autostart entry (its NotShowIn
  # fires under niri), dconf serves HM `dconf.settings`, gnome-keyring backs
  # the lock screen's PAM unlock. Same pattern as bluetooth in
  # features/desktop/nixos.nix.
  i18n.inputMethod.enable = false;
  programs.dconf.enable = true;
  services.gnome.gnome-keyring.enable = true;

  # The packages that make that session usable. The merged
  # `environment.systemPackages` order is load-bearing
  # (doc/dendritic-pattern.md), so the list keeps the importing host's
  # original order:
  #   noctalia           — the shell. From nixpkgs, not upstream's flake: the
  #                        flake pins its own nixpkgs (a second glibc, pipewire
  #                        and systemd generation, ~805 MiB marginal) or, with
  #                        `follows`, builds from source and misses its cache.
  #                        Revisit when nixos-26.05 carries 5.3.x.
  #   xwayland-satellite — niri's X11 integration needs this ON PATH; the
  #                        nixpkgs module passes enableXWayland = false, so
  #                        without it every X11 app is unavailable and niri
  #                        logs "error spawning xwayland-satellite".
  environment.systemPackages = [
    # Vial — GUI for configuring QMK/VIA keyboards in real time. Not a session
    # component: it rides this list because it shared the host's list, and its
    # udev ACL rule stays with the host — the serial it matches is that box's
    # keyboard. The package's own rule is MODE=0666 on EVERY hidraw device, so
    # it is not installed; the host's rule is that narrowed to Vial controllers.
    pkgs.vial

    # The niri session's shell and its X11 bridge, for the reasons given
    # above.
    pkgs.noctalia
    # TRIAL (uncommitted): greeter packages on PATH for the greeter user and
    # the polkit action under /share/polkit-1 (pkexec appearance sync).
    pkgs.noctalia-greeter
    pkgs.xwayland-satellite

    # Region picker for the screen_recorder plugin's default (region) source.
    pkgs.slurp

    # PATH tools for the community capture plugin alexander/screen-toolkit
    # (config/noctalia/config.toml); a missing tool degrades single features.
    # satty serves markup until the shell ships `annotate`, notify-send the
    # recording toast (the plugin's own notify API is text-only).
    # translate-shell (optional upstream) and hyprctl (Hyprland-only) are
    # omitted; pulseaudio is here only for pactl.
    pkgs.hyprpicker
    pkgs.tesseract
    pkgs.imagemagick
    pkgs.zbar
    pkgs.bc
    pkgs.wl-screenrec
    pkgs.wf-recorder
    pkgs.ffmpeg
    pkgs.mpv
    pkgs.pulseaudio
    pkgs.satty
    pkgs.libnotify
  ];
}
