# Auto-recovery for USB mice that fail enumeration at cold boot.
#
# WHY THIS EXISTS. The Razer Basilisk V3 intermittently misses the kernel's
# ~4 s enumeration window at cold power-on — on ANY port (the front-panel
# ports via the internal Genesys hub, `3-1.x`, AND the direct rear root port,
# `3-2`; the port choice narrows nothing, see doc/troubleshooting.md). The
# kernel then gives up with "unable to enumerate" and never retries: the mouse
# stays dead until a replug. Observed 2026-09-08 (front, after ~11 h off) and
# 2026-09-09 (rear, after ~5.5 h off); warm restarts and some cold boots
# enumerate cleanly, so it is a coin flip per power-on, not port-dependent.
#
# THE FIX is to emulate the replug: unbind/rebind of the mouse's xHCI
# controller. On this board each xHCI PCI function drives two root hubs, so
# bouncing `c8:00.0` resets exactly buses 3+4 — the mouse's port plus the
# front-panel hub chain, both empty of anything else at boot. The BT radio
# (bus 1, `c6:00.4`) and the Corne keyboard (bus 7, `c8:00.4`) sit on
# SEPARATE PCI functions and are untouched — verified 2026-09-09 via
# readlink of /sys/bus/usb/devices/usbN. If unbind fails (controller wedged),
# a module reload is the last resort.
#
# The service runs at boot, after a settle delay, and only acts when a mouse
# is expected-but-absent — idempotent on the (majority) boots that enumerate
# cleanly. It is a oneshot: nothing watches USB afterwards, so a failure later
# in a session is still a manual replug (or `sudo systemctl start
# usb-mouse-recovery`).

{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Vendor:product of the Razer Basilisk V3, and the xHCI controller whose
  # root hub carries it (c8:00.0 → buses 3/4). Hardcoded literals, same
  # pattern as loopback-rebuild's pinned keys: they are properties of this
  # exact board + mouse, and an option layer would only obscure that.
  mouseId = "1532:0099";
  xhciPci = "0000:c8:00.0";

  recoveryScript = pkgs.writeShellScript "usb-mouse-recovery" ''
    set -u

    mousePresent() {
      ${pkgs.usbutils}/bin/lsusb -d ${mouseId} >/dev/null 2>&1
    }

    # Idempotence guard: nothing to do when the mouse made it up this boot.
    if mousePresent; then
      echo "usb-mouse-recovery: mouse ${mouseId} present, nothing to do"
      exit 0
    fi

    echo "usb-mouse-recovery: mouse ${mouseId} absent — bouncing xHCI controller ${xhciPci}"

    # Mechanism 1: unbind+rebind of the xHCI PCI device. `|| true` so a
    # failed unbind still reaches the module reload below.
    if echo "${xhciPci}" > /sys/bus/pci/drivers/xhci_hcd/unbind 2>/dev/null; then
      sleep 1
      echo "${xhciPci}" > /sys/bus/pci/drivers/xhci_hcd/bind || true
      sleep 2
    else
      echo "usb-mouse-recovery: unbind failed — falling back to module reload"
      ${pkgs.kmod}/bin/modprobe -r xhci_hcd 2>/dev/null || true
      sleep 1
      ${pkgs.kmod}/bin/modprobe xhci_hcd || true
      sleep 2
    fi

    if mousePresent; then
      echo "usb-mouse-recovery: mouse recovered"
    else
      echo "usb-mouse-recovery: mouse still absent after bounce — manual replug needed"
      exit 1
    fi
  '';
in
{
  systemd.services.usb-mouse-recovery = {
    description = "Bounce the xHCI controller when the USB mouse failed to enumerate at boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    serviceConfig = {
      Type = "oneshot";
      # Sleep first, THEN check: long enough that a slow-but-working
      # enumeration has landed (the kernel itself gives up after ~4 s),
      # short enough that recovery finishes before anyone reaches for the
      # mouse. udev settle alone does not bound device enumeration — the
      # kernel's own retry window does.
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 8";
      ExecStart = "${recoveryScript}";
      # The bind/unbind paths are sysfs writes owned by root; no hardening
      # sandbox can allow those, so this runs unsandboxed on purpose.
      PrivateDevices = false;
      ProtectProc = "no";
    };
  };
}
