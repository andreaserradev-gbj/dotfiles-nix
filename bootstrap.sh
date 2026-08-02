#!/usr/bin/env bash
# bootstrap.sh — one-command fresh install of any host defined in this flake.
#
# Boot the NixOS 26.05 minimal ISO for the TARGET's architecture, then:
#   curl -fsSL https://raw.githubusercontent.com/andreaserradev-gbj/dotfiles-nix/main/bootstrap.sh | sudo bash -s -- <host>
#
# The `-s --` is load-bearing: without it bash consumes <host> as its own
# argument and the script silently installs the default instead.
#
# <host> defaults to `nixos`, the aarch64 UTM dev VM.
set -euo pipefail
export NIX_CONFIG="experimental-features = nix-command flakes"

REPO="andreaserradev-gbj/dotfiles-nix"

if [ "$#" -gt 1 ]; then
  echo "!! Too many arguments. Usage: bootstrap.sh [host]" >&2
  exit 1
fi

# ${1-nixos}, NOT ${1:-nixos}: the default must apply only when the argument is
# genuinely absent. Under :- an explicit empty string — `bash -s -- "$TARGET"`
# with TARGET unset — would silently install the VM instead of failing.
HOST="${1-nixos}"

# Host flake-attr -> host directory, and the unknown-host guard, in one place.
#
# The two names differ for the VM: its flake attr is `nixos` because that must
# match networking.hostName (what `nh` resolves against), but its directory is
# hosts/vm. Deriving hosts/$HOST/ directly would fetch a 404 for the VM alone.
# Keep this list in step with flake.nix's nixosConfigurations.
case "$HOST" in
  nixos) HOST_DIR="vm" ;;
  geekom) HOST_DIR="geekom" ;;
  *)
    echo "!! Unknown host: '$HOST'" >&2
    echo "   Known hosts: nixos geekom" >&2
    exit 1
    ;;
esac

FLAKE="github:${REPO}#${HOST}"
DISKO_CFG="https://raw.githubusercontent.com/${REPO}/main/hosts/${HOST_DIR}/disk-config.nix"

if [ "$(id -u)" -ne 0 ]; then
  echo "!! Must run as root — pipe into 'sudo bash'." >&2
  exit 1
fi

# --- [1/4] Pre-flight -------------------------------------------------------
# Fetch and vet the disk layout BEFORE anything destructive happens. A wrong
# path costs two seconds here instead of surfacing after partitioning, on
# hardware you are standing in front of.
echo ">>> [1/4] pre-flight: $DISKO_CFG"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$DISKO_CFG" -o "$tmp/disk-config.nix"

# Read the device back out of the layout we actually fetched, so the
# confirmation below names the disk disko will really act on.
DEVICE="$(sed -n 's/^[[:space:]]*device[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$tmp/disk-config.nix" | head -1)"
if [ -z "$DEVICE" ]; then
  echo "!! No device path found in $DISKO_CFG" >&2
  exit 1
fi
case "$DEVICE" in
  *PLACEHOLDER*)
    echo "!! ${HOST}'s disk-config.nix still holds a placeholder device path:" >&2
    echo "     $DEVICE" >&2
    echo "   Replace it with the real by-id path and push before installing." >&2
    exit 1
    ;;
esac

# --- [2/4] Confirm ----------------------------------------------------------
# stdin is the piped SCRIPT, not the keyboard, so the prompt must read the
# terminal directly. A bare `read` here would eat the script's own text.
echo ""
echo "    host:   $HOST  ($FLAKE)"
echo "    layout: $DISKO_CFG"
echo "    DISK:   $DEVICE"
echo "            ^ WILL BE WIPED — ALL DATA ON IT DESTROYED"
echo ""
if ! { : < /dev/tty; } 2>/dev/null; then
  echo "!! No terminal to confirm on; refusing to wipe unattended." >&2
  exit 1
fi
read -r -p ">>> [2/4] Type the host name to proceed ($HOST): " reply < /dev/tty
if [ "$reply" != "$HOST" ]; then
  echo "Aborted — nothing was touched." >&2
  exit 1
fi

# --- [3/4] Install ----------------------------------------------------------
echo ">>> [3/4] disko: partition + format + mount $DEVICE  (THIS WIPES THE DISK)"
umount -R /mnt 2>/dev/null || true # clean up any leftover mounts
nix run github:nix-community/disko/latest -- \
  --mode destroy,format,mount --yes-wipe-all-disks "$tmp/disk-config.nix"

echo ">>> [4/4] nixos-install: build system + \$HOME from the flake — $FLAKE"
nixos-install --flake "$FLAKE" --no-root-passwd

echo ""
echo ">>> Install complete."
echo "    1. Detach the install medium (UTM: Drive -> eject; hardware: unplug the USB)."
echo "    2. reboot"
echo "    Then SSH in with your key. Console session is whatever hosts/${HOST_DIR}/ configures."
