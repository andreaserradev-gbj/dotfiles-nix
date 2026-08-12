# The desktop seam. Imported by EVERY host through commonModules, but wholly
# inert unless the host sets `local.desktop.enable`. The VM leaves it off: it
# runs a cage+foot kiosk on a software renderer and must not grow a GDM.
#
# `local.*` is this repo's own option namespace — nothing upstream owns it, so
# there is no collision risk as more seams (hyprland, gaming, …) get added.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.desktop;
in
{
  options.local.desktop.enable = lib.mkEnableOption "the GNOME desktop stack (GDM, GNOME, pipewire, Bluetooth, printing, scanning, Brave, PDF tools)";

  config = lib.mkIf cfg.enable {
    # GNOME's session under GDM is Wayland by default; this is what supplies
    # XWayland, so X11-only applications still run.
    services.xserver.enable = true;

    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;

    # Audio: pipewire, with the pulseaudio server it replaces switched off
    # explicitly so the two can never both be enabled.
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # Bluetooth, EXPLICITLY — and this line is not redundant.
    #
    # GNOME already sets `hardware.bluetooth.enable = mkDefault true` and
    # installs gnome-bluetooth, so Bluetooth would appear to work with this
    # line deleted. But it would be working as a SIDE EFFECT of GNOME being
    # installed. The planned Hyprland swap removes GNOME and would silently
    # take Bluetooth with it — on a machine whose keyboard may be Bluetooth.
    # An explicit `true` overrides a `mkDefault true` with no conflict.
    #
    # NOT set here on purpose: `powerOnBoot` (already true by default), and
    # `services.blueman.enable` — GNOME owns the Bluetooth frontend; blueman
    # is the Hyprland-era REPLACEMENT for it, not something to run alongside.
    hardware.bluetooth.enable = true;

    # Printing, plus the mDNS that finds the printer. Same shape as Bluetooth
    # above, and for the same reason.
    #
    # Measured before this was written: the VM evaluates `services.avahi.enable
    # = false` and geekom evaluates `true`, with no avahi anywhere in this repo.
    # GNOME turns it on. Swap GNOME for Hyprland and printer discovery vanishes
    # with it — silently, because cupsd would still be running and the printer
    # would simply stop appearing. Hence the explicit `true`.
    #
    # `nssmdns4` is off by default and is what resolves `.local` names through
    # NSS, so a stored `ipp://<host>.local` queue keeps working. Avahi's
    # `openFirewall` already defaults to true, so UDP 5353 needs no line here.
    #
    # NO DRIVERS ON PURPOSE. The target is an HP ENVY 4500, which the Mac holds
    # as `dnssd://HP ENVY 4500 series [B1C0AA]._ipp._tcp.local.` — an `_ipp._tcp`
    # record, so it speaks IPP directly and CUPS can drive it with no PPD.
    # `hplip` is the fallback if that turns out to be false, not the starting
    # point: it is a large stack to add before driverless has been disproved.
    services.printing.enable = true;
    services.avahi = {
      enable = true;
      nssmdns4 = true;
    };

    # Scanning, driverless over the same mDNS the printer was found on.
    # Measured before this was written: the device advertises `_uscan._tcp` on
    # port 8080 with `rs=/eSCL`, and `GET /eSCL/ScannerCapabilities` returns
    # eSCL 2.1 XML. Platen only, no feeder, so no duplex option will appear.
    #
    # THREE THINGS DELIBERATELY NOT SET, each the obvious-looking move:
    #   - the `scanner` group. eSCL is HTTP to a network address, so there is
    #     no device node and udev permissions change nothing. That group is
    #     for USB scanners.
    #   - `hardware.sane.openFirewall`. It opens ports for `saned`, which
    #     shares a LOCAL scanner outwards. This host is the client.
    #   - `hplip`. The device also advertises `_scanner._tcp`, HP's own scan
    #     protocol behind the `hpaio` backend. That is the heavier route and
    #     eSCL answered on the first try.
    #
    # No frontend is added either: GNOME already installs simple-scan
    # ("Document Scanner"). Unlike the avahi case above, that side effect is a
    # safe one to inherit — losing it at the Hyprland swap means no scanner
    # GUI, which is obvious, rather than a scanner that silently stops being
    # found while the daemon keeps running.
    hardware.sane.enable = true;
    hardware.sane.extraBackends = [ pkgs.sane-airscan ];

    # sane-backends carries its OWN `escl` backend, so before this line
    # `scanimage -L` listed one scanner twice: `airscan:e0:HP ENVY 4500 series
    # [B1C0AA]`, re-discovered by name, and `escl:http://192.168.68.52:8080`,
    # a literal address baked in at discovery time.
    #
    # The printer now has a DHCP reservation, so this is not fixing a live
    # break — it removes a choice that has no right answer visible in a GUI.
    # Only the name-based entry survives a router replacement or a move to a
    # different network, and a frontend that remembered the wrong one would
    # fail much later with nothing pointing at the cause.
    #
    # The cost is real: this is the fallback if sane-airscan ever regresses.
    # Re-enable by deleting this line, not by adding a different backend.
    hardware.sane.disabledDefaultBackends = [ "escl" ];

    # Brave has no NixOS module (unlike programs.firefox), so it goes in as a
    # plain package. It is MPL-2.0 with meta.unfree = false, so it needs NO
    # allowUnfreePredicate entry in common.nix and none should be added.
    #
    # No version is named here on purpose. It moved on the first lock bump
    # after this comment was written, and a stale literal reads as a verified
    # fact. Nothing is lost: evaluation checks the claim that matters, so if a
    # future bump makes Brave unfree, eval will say so.
    #
    # PDF work: three tools because it is three unrelated jobs, and no single
    # Linux application covers them the way Acrobat does.
    #   xournalpp   — annotate, and stamp a signature image onto a page
    #   pdfarranger — reorder, merge, split, rotate, delete pages
    #   imagemagick — `magick sig.png -fuzz 20% -transparent white out.png`,
    #                 which is what makes a scanned signature usable on top of
    #                 anything that is not plain white paper
    #
    # NOT added: libreoffice. Draw is the only route on Linux to editing text
    # already inside a PDF, and it reimports the page as loose objects, so the
    # layout drifts. Over a gigabyte for the one PDF job it does badly. Add it
    # if an office suite is wanted, not as a PDF editor.
    #
    # Nothing here signs a PDF in the cryptographic sense. A stamped image is a
    # picture: no certificate, no tamper evidence, and liftable by anyone with
    # the file. PAdES/CAdES would need a different tool and a real certificate.
    environment.systemPackages = [
      pkgs.brave
      pkgs.xournalpp
      pkgs.pdfarranger
      pkgs.imagemagick
    ];
  };
}
