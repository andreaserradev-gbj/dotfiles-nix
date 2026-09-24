#!/usr/bin/env bash
# bootstrap.sh — one-command fresh install of any host defined in this flake.
#
# Boot the NixOS 26.05 minimal ISO for the TARGET's architecture, then:
#   curl -fsSL https://raw.githubusercontent.com/andreaserradev-gbj/dotfiles-nix/main/bootstrap.sh | sudo bash -s -- <host>
#
# The `-s --` is load-bearing: without it bash reads <host> as a script
# filename and exits 127 without installing anything.
#
# <host> is required and must be one of `nixos`, `geekom`, `hplaptop`.
set -euo pipefail
export NIX_CONFIG="experimental-features = nix-command flakes"

REPO="andreaserradev-gbj/dotfiles-nix"

# Pinned disko release. HAND-MAINTAINED — this script runs from a live ISO,
# outside the flake, so it cannot inherit flake.lock's pin and needs its own
# string. Bump it deliberately; nothing here will do it for you, and nothing
# fails if it goes stale.
#
# Pinned to the COMMIT, not the tag: a tag is a movable ref, and this script
# is fetched over the network and run as root against a blank disk — the one
# place in the repo where "whatever that name points at today" is the wrong
# semantics. The tag lives in the trailing comment as the human bump handle.
#
# Pinned 2026-08-02, when disko's `latest` tag and v1.13.0 both peeled to this
# same commit — so the pin changed nothing about what an install fetched that
# day. Resolve a newer candidate with:
#   git ls-remote --tags https://github.com/nix-community/disko
DISKO_REF="de5708739256238fb912c62f03988815db89ec9a" # v1.13.0

# The host is REQUIRED, never defaulted: this script wipes the disks the host's
# layout declares, and a wrong guess costs a machine.
if [ "$#" -ne 1 ]; then
  echo "!! Usage: bootstrap.sh <host>" >&2
  exit 1
fi

HOST="$1"

# Host flake-attr -> host directory, and the unknown-host guard, in one place.
#
# The two names differ for the VM: its flake attr is `nixos` because that must
# match networking.hostName (what `nh` resolves against), but its directory is
# hosts/vm. Deriving hosts/$HOST/ directly would fetch a 404 for the VM alone.
# Keep this list in step with flake.nix's nixosConfigurations.
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
# Fetch and vet the disk layout BEFORE anything destructive happens. A wrong
# path costs two seconds here instead of surfacing after partitioning, on
# hardware you are standing in front of.
echo ">>> [1/4] pre-flight: $DISKO_CFG"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$DISKO_CFG" -o "$tmp/disk-config.nix"

# Read the device(s) back out of the layout we actually fetched, so the
# confirmation below names the disk(s) disko will really act on.
#
# EVERY `device =` match, not `head -1`. --yes-wipe-all-disks wipes every disk
# the layout declares; showing only the first would have the operator confirm
# one disk and lose several.
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
# terminal directly. A bare `read` here would eat the script's own text.
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
umount -R /mnt 2>/dev/null || true # clean up any leftover mounts
nix run "github:nix-community/disko/${DISKO_REF}" -- \
  --mode destroy,format,mount --yes-wipe-all-disks "$tmp/disk-config.nix"

echo ">>> [4/4] nixos-install: build system + \$HOME from the flake — $FLAKE"
nixos-install --flake "$FLAKE" --no-root-passwd

echo ""
echo ">>> Install complete."
echo "    1. Detach the install medium (UTM: Drive -> eject; hardware: unplug the USB)."
echo "    2. reboot"
echo "    Then SSH in with your key. Console session is whatever hosts/${HOST_DIR}/ configures."
