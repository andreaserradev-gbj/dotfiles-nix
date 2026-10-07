# The desktop seam: imported by every host through commonModules, but wholly
# inert unless the host sets `local.desktop.enable`. The VM leaves it off — it
# runs a cage+foot kiosk on a software renderer and must not grow a GDM.
# `local.*` is this repo's own option namespace; nothing upstream owns it.
{
  config,
  lib,
  pkgs,
  user,
  ...
}:

let
  cfg = config.local.desktop;
in
{
  options.local.desktop = {
    enable = lib.mkEnableOption "the GNOME desktop stack (GDM, GNOME, pipewire, Bluetooth, printing, scanning, Brave, PDF tools)";

    # `full` = PaperWM + Catppuccin theming (geekom); `vanilla` = plain GNOME
    # (hplaptop). The HM half (modules/home/desktop.nix, modules/home/gtk.nix)
    # reads this and gates the PaperWM/Catppuccin dconf + GTK config on
    # `variant == "full"`.
    variant = lib.mkOption {
      type = lib.types.enum [
        "full"
        "vanilla"
      ];
      default = "full";
      description = "Desktop variant: `full` enables PaperWM + Catppuccin theming, `vanilla` ships plain GNOME.";
    };

    libreoffice.enable = lib.mkEnableOption "LibreOffice";
  };

  config = lib.mkIf cfg.enable {
    # Supplies XWayland, so X11-only applications still run on GNOME's Wayland
    # session.
    services.xserver.enable = true;

    # Same per-host field as the console keymap (common.nix), so TTY and GUI can
    # never disagree. Feeds GDM's greeter and the session's XKB defaults; GNOME's
    # per-user input sources are declarative in modules/home/desktop.nix.
    services.xserver.xkb.layout = user.keyboardLayout or "us";

    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;

    # GDM theming deliberately NOT applied: the one piece worth styling (the
    # cursor) is blocked by the packaging issue in modules/home/gtk.nix, and the
    # rest is not worth the regret-risk — the login screen is up for ~2s per
    # boot, and a failed greeter means a black screen recovered via TTY.

    # pipewire, with the pulseaudio server it replaces switched off explicitly
    # so the two can never both be enabled.
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # Bluetooth, EXPLICITLY — and this line is not redundant. GNOME already sets
    # `hardware.bluetooth.enable = mkDefault true`, so with this line deleted
    # Bluetooth would appear to work, but as a SIDE EFFECT of GNOME being
    # installed: the planned Hyprland swap removes GNOME and would silently take
    # it along, on a machine whose keyboard may be Bluetooth. An explicit `true`
    # overrides a `mkDefault true` with no conflict.
    #
    # NOT set on purpose: `powerOnBoot` (already true by default), and
    # `services.blueman.enable` — GNOME owns the Bluetooth frontend; blueman is
    # the Hyprland-era replacement for it, not a companion.
    hardware.bluetooth.enable = true;

    # Audio sinks reconnect to their last host on their own when they power on,
    # but a host that vanished mid-session (reboot) gets no re-dial, and GNOME
    # never dials out itself. The connect must happen in the USER session, not
    # early at boot: a device connected during the GDM greeter phase negotiates
    # its A2DP transport against the greeter's PipeWire, and the transport dies
    # when the real session replaces it — connected at the login screen,
    # dropped at login. Ordered after graphical-session.target, the
    # connection binds to the session audio stack that owns the endpoints.
    #
    # Every bluetoothctl call is wrapped in `timeout`: against a powered-off or
    # sleeping speaker the D-Bus calls block indefinitely (observed: a connect
    # loop stalled 2 minutes and was killed by the unit timeout). Devices that
    # are merely absent therefore cost one bounded, logged attempt each.
    systemd.user.services.bluetooth-reconnect = {
      description = "Reconnect trusted Bluetooth devices at login";
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      path = [ pkgs.bluez ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "3min";
      };
      script = ''
        for attempt in 1 2 3; do
          pending=0
          # A wedged bluetoothd makes these calls block indefinitely, and a
          # killed call must look PENDING (retry), never like "nothing to do":
          # an empty device list or an unreadable device would otherwise turn
          # the whole run into a silent no-op.
          devs="$(timeout -k 5 10 bluetoothctl devices Paired)" || {
            echo "attempt $attempt: devices query failed"
            pending=1
            sleep 5
            continue
          }
          macs="$(echo "$devs" | cut -d ' ' -f 2)"
          for mac in $macs; do
            rc=0
            info="$(timeout -k 5 10 bluetoothctl info "$mac" 2>&1)" || rc=$?
            if [ "$rc" -ne 0 ]; then
              echo "attempt $attempt: info $mac failed (rc=$rc)"
              pending=1
              continue
            fi
            echo "$info" | grep -q 'Connected: yes' && continue
            echo "$info" | grep -q 'Trusted: yes' || continue
            pending=1
            echo "attempt $attempt: connecting $mac"
            timeout -k 5 20 bluetoothctl connect "$mac" 2>&1 || true
          done
          [ "$pending" -eq 0 ] && exit 0
          sleep 5
        done
        exit 0
      '';
    };

    # Observed on a reboot: a connect racing the greeter→session endpoint
    # churn hit a BlueZ a2dp.c assertion and bluetoothd died (SIGABRT) for the
    # whole session — with no Restart= in the unit. The user-unit timing above
    # avoids the race window; this makes the residual crash self-heal.
    systemd.services.bluetooth.serviceConfig.Restart = "on-failure";

    # Printing, plus the mDNS that finds the printer. Same shape as Bluetooth
    # above, for the same reason: GNOME turns avahi on, so printer discovery
    # would vanish with the Hyprland swap while cupsd kept running. `nssmdns4`
    # resolves `.local` names through NSS, so a stored `ipp://<host>.local`
    # queue keeps working. NO DRIVERS ON PURPOSE: the target advertises
    # `_ipp._tcp`, so CUPS drives it with no PPD; `hplip` is the fallback if
    # that turns out to be false, not the starting point.
    services.printing.enable = true;
    services.avahi = {
      enable = true;
      nssmdns4 = true;
    };

    # Scanning, driverless over the same mDNS the printer was found on; the
    # device advertises `_uscan._tcp` with eSCL, which answered on the first try.
    #
    # THREE THINGS DELIBERATELY NOT SET, each the obvious-looking move:
    #   - the `scanner` group: eSCL is HTTP to a network address, so there is no
    #     device node and udev permissions change nothing.
    #   - `hardware.sane.openFirewall`: it opens ports for `saned`, which shares
    #     a LOCAL scanner outwards. This host is the client.
    #   - `hplip`: the device also advertises `_scanner._tcp`, HP's own heavier
    #     route behind the `hpaio` backend.
    #
    # No frontend is added either: GNOME installs simple-scan ("Document
    # Scanner"), and losing that at the Hyprland swap is obvious — no scanner
    # GUI — rather than a scanner that silently stops being found.
    hardware.sane.enable = true;
    hardware.sane.extraBackends = [ pkgs.sane-airscan ];

    # `sane-backends` carries its OWN `escl` backend, which listed the printer
    # twice: by name, and by a literal address baked in at discovery time. Only
    # the name-based entry survives a router replacement or a move to another
    # network, and a frontend that remembered the wrong one would fail much later
    # with nothing pointing at the cause. The cost is real: this is the fallback
    # if sane-airscan ever regresses — re-enable by deleting this line.
    hardware.sane.disabledDefaultBackends = [ "escl" ];

    # Brave has no NixOS module (unlike programs.firefox), so it goes in as a
    # plain package. MPL-2.0 with meta.unfree = false: no allowUnfreePredicate
    # entry in common.nix, and none should be added. No version is named on
    # purpose — a stale literal reads as a verified fact, and eval is the check.
    #
    # PDF work: three tools for three unrelated jobs.
    #   xournalpp   — annotate, and stamp a signature image onto a page
    #   pdfarranger — reorder, merge, split, rotate, delete pages
    #   imagemagick — makes a scanned signature usable on anything that is not
    #                 plain white paper: `magick sig.png -fuzz 20% -transparent white out.png`
    #
    # No libreoffice here: Draw is the only route on Linux to editing text
    # inside a PDF, and it reimports the page as loose objects, drifting the
    # layout — over a gigabyte for the one PDF job it does badly. The
    # `local.desktop.libreoffice.enable` option exists for the host that needs
    # it for office files (hplaptop).
    environment.systemPackages = [
      pkgs.brave
      pkgs.xournalpp
      pkgs.pdfarranger
      pkgs.imagemagick
    ]
    # Dash to Dock — auto-hide bottom dock, on both variants. NOT Dash to
    # *Panel*: that is the different, incompatible extension PaperWM's list
    # names. nixpkgs gates the extension on its `shell-version` metadata, so a
    # GNOME bump fails at eval until a matching release lands.
    ++ [ pkgs.gnomeExtensions.dash-to-dock ]
    # PaperWM — scrollable tiling. Here and not in the HM half because GNOME
    # Shell extensions are system-wide packages loaded from the system profile,
    # while the ENABLE state is per-user dconf (modules/home/desktop.nix). Gated
    # on `variant == "full"`; PaperWM auto-disables the three incompatible
    # settings itself, so nothing is set for those here.
    ++ lib.optionals (cfg.variant == "full") [ pkgs.gnomeExtensions.paperwm ]
    # LibreOffice, its own sub-option and default false: geekom does not pull the
    # ~1GB closure. Only hplaptop enables it — Word/Excel compatibility for HR
    # work.
    ++ lib.optionals cfg.libreoffice.enable [ pkgs.libreoffice ];
  };
}
