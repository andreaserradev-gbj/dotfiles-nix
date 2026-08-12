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
  options.local.desktop.enable = lib.mkEnableOption "the GNOME desktop stack (GDM, GNOME, pipewire, Bluetooth, printing, Brave)";

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

    # Brave has no NixOS module (unlike programs.firefox), so it goes in as a
    # plain package. Verified at the pin: 1.92.139, MPL-2.0, meta.unfree =
    # false — so it needs NO allowUnfreePredicate entry in common.nix and none
    # should be added. If a future bump makes it unfree, eval will say so.
    environment.systemPackages = [ pkgs.brave ];
  };
}
