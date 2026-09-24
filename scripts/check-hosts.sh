#!/usr/bin/env bash
# check-hosts.sh — evaluate EVERY host and print its system drvPath. This is the
# multi-host regression gate: `nix flake check` does not evaluate
# nixosConfigurations at all, so a typo in the host you are NOT sitting on stays
# invisible until the day you build it. Evaluation is architecture-independent,
# so the x86_64 hosts are checked from an aarch64 VM and vice versa.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Nix evaluates a flake from the git INDEX, not the working tree: an untracked
# file is invisible, and the error it causes ("path does not exist") points
# nowhere near the cause — warn loudly. The `-z` + NUL-delimited read loop below
# keeps a path holding a space or a `*` from splitting into bogus filenames.
if [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo "!! WARNING: untracked files — nix will NOT see these:" >&2
  while IFS= read -r -d '' f; do
    printf '!!   %s\n' "$f" >&2
  done < <(git ls-files --others --exclude-standard -z)
  echo "!! Run 'git add' before trusting a green result below." >&2
  echo >&2
fi

# The host list is DERIVED from the flake, not restated here: a hardcoded list
# would silently stop covering a host the moment one is added to flake.nix.
HOSTS="$(nix eval --raw .#nixosConfigurations \
  --apply 'cs: builtins.concatStringsSep " " (builtins.attrNames cs)')"
if [ -z "$HOSTS" ]; then
  echo "!! No nixosConfigurations found in the flake." >&2
  exit 1
fi

# The drvPath doubles as the reference hash for the PRD's phase gates: record it
# before a change, compare after — a host you did not mean to touch must not move.

# stderr is deliberately NOT captured: Nix emits `warnings` — including the
# hardware-configuration.nix placeholder sentinel — as evaluation traces there,
# and hiding them would remove the one warning this gate exists to surface.
status=0
for host in $HOSTS; do
  echo "-- evaluating ${host}"
  if drv="$(nix eval --raw ".#nixosConfigurations.${host}.config.system.build.toplevel.drvPath")"; then
    printf '%-8s %s\n' "$host" "$drv"
  else
    printf '%-8s EVAL FAILED\n' "$host"
    status=1
  fi
done

exit "$status"
