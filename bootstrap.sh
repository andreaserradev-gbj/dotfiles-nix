#!/usr/bin/env bash
# bootstrap.sh — one-command fresh install onto a blank UTM aarch64 VM.
# Boot the NixOS 26.05 aarch64 minimal ISO, then:
#   curl -sL https://raw.githubusercontent.com/andreaserradev-gbj/dotfiles-nix/main/bootstrap.sh | sudo bash
set -euo pipefail
export NIX_CONFIG="experimental-features = nix-command flakes"

REPO="andreaserradev-gbj/dotfiles-nix"
FLAKE="github:${REPO}#nixos"
DISKO_CFG="https://raw.githubusercontent.com/${REPO}/main/nixos/disk-config.nix"

if [ "$(id -u)" -ne 0 ]; then
  echo "!! Must run as root — pipe into 'sudo bash'." >&2
  exit 1
fi

echo ">>> [1/2] disko: partition + format + mount /dev/vda  (THIS WIPES THE DISK)"
umount -R /mnt 2>/dev/null || true # clean up any leftover mounts
tmp="$(mktemp -d)"
curl -fsSL "$DISKO_CFG" -o "$tmp/disk-config.nix"
nix run github:nix-community/disko/latest -- \
  --mode destroy,format,mount --yes-wipe-all-disks "$tmp/disk-config.nix"

echo ">>> [2/2] nixos-install: build system + \$HOME from the flake — $FLAKE"
nixos-install --flake "$FLAKE" --no-root-passwd

echo ""
echo ">>> Install complete."
echo "    1. In UTM: detach the ISO (Drive -> eject)."
echo "    2. reboot"
echo "    Boots into the cage+foot console (autologin). SSH from the Mac with your key."
