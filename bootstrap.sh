#!/usr/bin/env bash
# bootstrap.sh — one-command fresh install of any host defined in this flake.
#
# Boot the NixOS 26.05 minimal ISO for the TARGET's architecture, then:
#   curl -fsSL https://raw.githubusercontent.com/andreaserradev-gbj/dotfiles-nix/main/bootstrap.sh | sudo bash -s -- <host>
#
# `<host>` must be one of `nixos`, `geekom`, `hplaptop`. The `-s --` is
# load-bearing: without it bash reads <host> as a script filename and exits 127.
set -euo pipefail
export NIX_CONFIG="experimental-features = nix-command flakes"

REPO="andreaserradev-gbj/dotfiles-nix"

# Pinned disko release, HAND-MAINTAINED — this runs from a live ISO, outside the
# flake, so it cannot inherit flake.lock's pin. Pinned to the COMMIT, not the tag:
# a tag is a movable ref, and this script is fetched over the network and run as
# root against a blank disk. The trailing comment is the human bump handle
# (`git ls-remote --tags https://github.com/nix-community/disko`).
DISKO_REF="de5708739256238fb912c62f03988815db89ec9a" # v1.13.0

# The host is REQUIRED, never defaulted: this script wipes the disks the host's
# layout declares, and a wrong guess costs a machine.
if [ "$#" -ne 1 ]; then
  echo "!! Usage: bootstrap.sh <host>" >&2
  exit 1
fi

HOST="$1"

# Host flake-attr -> host directory + the unknown-host guard, in one place; keep
# in step with flake.nix. The names differ for the VM only: attr `nixos` (matches
# networking.hostName, what `nh` resolves against), directory hosts/vm.
case "$HOST" in
  nixos) HOST_DIR="vm" ;;
  geekom) HOST_DIR="geekom" ;;
  hplaptop) HOST_DIR="hplaptop" ;;
  *)
    echo "!! Unknown host: '$HOST'" >&2
    echo "   Known hosts: nixos geekom hplaptop" >&2
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
# Fetch and vet the disk layout BEFORE anything destructive happens: a wrong path
# here costs two seconds instead of surfacing after partitioning.
echo ">>> [1/4] pre-flight: $DISKO_CFG"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$DISKO_CFG" -o "$tmp/disk-config.nix"

# Read the device(s) out of the layout we actually fetched, so the confirmation
# names the disk(s) disko acts on. EVERY `device =` match — showing only the first
# (`head -1`) would have the operator confirm one disk and lose several.
DEVICES="$(sed -n 's/^[[:space:]]*device[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$tmp/disk-config.nix")"
if [ -z "$DEVICES" ]; then
  echo "!! No device path found in $DISKO_CFG" >&2
  exit 1
fi
case "$DEVICES" in
  *PLACEHOLDER*)
    echo "!! ${HOST}'s disk-config.nix still holds a placeholder device path:" >&2
    printf '     %s\n' "$DEVICES" >&2
    echo "   Replace it with the real by-id path and push before installing." >&2
    exit 1
    ;;
esac
DEVICE_COUNT="$(printf '%s\n' "$DEVICES" | wc -l | tr -d ' ')"

# --- [2/4] Confirm ----------------------------------------------------------
# stdin is the piped SCRIPT, not the keyboard, so the prompt must read the
# terminal directly: a bare `read` would eat the script's own text.
echo ""
echo "    host:   $HOST  ($FLAKE)"
echo "    layout: $DISKO_CFG"
if [ "$DEVICE_COUNT" -eq 1 ]; then
  echo "    DISK:   $DEVICES"
else
  echo "    DISKS:  ($DEVICE_COUNT)"
  while IFS= read -r dev; do printf '            %s\n' "$dev"; done <<EOF
$DEVICES
EOF
fi
echo "            ^ WILL BE WIPED — ALL DATA ON THEM DESTROYED"
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
echo ">>> [3/4] disko: partition + format + mount (THIS WIPES THE DISK)"
umount -R /mnt 2>/dev/null || true
nix run "github:nix-community/disko/${DISKO_REF}" -- \
  --mode destroy,format,mount --yes-wipe-all-disks "$tmp/disk-config.nix"

echo ">>> [4/4] nixos-install: build system + \$HOME from the flake — $FLAKE"
nixos-install --flake "$FLAKE" --no-root-passwd

echo ""
echo ">>> Install complete."
echo "    1. Detach the install medium (UTM: Drive -> eject; hardware: unplug the USB)."
echo "    2. reboot"
echo "    Then SSH in with your key. Console session is whatever hosts/${HOST_DIR}/ configures."
