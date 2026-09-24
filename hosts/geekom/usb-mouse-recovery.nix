# Auto-recovery for USB mice that fail enumeration at cold boot: bounce the
# mouse's xHCI controller, emulating the replug. The Razer Basilisk V3 misses the
# kernel's ~4 s retry window on ANY port and the kernel never retries; bouncing
# `c8:00.0` resets buses 3+4 only (the mouse's port plus the front-panel hub
# chain) — BT radio and Corne sit on separate PCI functions (doc/troubleshooting.md).
{
  pkgs,
  ...
}:

let
  # Vendor:product of the Razer Basilisk V3 and the xHCI controller whose root hub
  # carries it (c8:00.0 → buses 3/4) — literals like loopback-rebuild's pinned keys.
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
  # Runs once at boot and only when the mouse is absent; nothing watches USB
  # afterwards, so a failure later in the session is still a manual replug.
  systemd.services.usb-mouse-recovery = {
    description = "Bounce the xHCI controller when the USB mouse failed to enumerate at boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    serviceConfig = {
      Type = "oneshot";
      # Sleep first, then check: long enough for a slow-but-working enumeration to
      # land, short enough to recover before anyone reaches for the mouse.
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 8";
      ExecStart = "${recoveryScript}";
      # The sysfs bind/unbind paths are root-owned writes no hardening sandbox can
      # allow, so this runs unsandboxed on purpose.
      PrivateDevices = false;
      ProtectProc = "no";
    };
  };
}
