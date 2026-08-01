#!/usr/bin/env bash
# check-hosts.sh — evaluate EVERY host and print its system drvPath.
#
# This is the multi-host regression gate. `nix flake check` does not evaluate
# nixosConfigurations at all, so without this a typo in whichever host you are
# NOT sitting on stays invisible until the day you try to build it — which,
# for a machine that does not exist yet, is the worst possible day.
#
# Evaluation is architecture-independent, so this checks x86_64 geekom from
# the aarch64 VM and vice versa. It BUILDS NOTHING and touches no system.
#
# The drvPath doubles as the reference hash for the PRD's phase gates: record
# it before a change, compare after. A host you did not mean to touch must not
# move. A host that moves for a reason you cannot name has not been understood.
set -euo pipefail

HOSTS="nixos geekom"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Nix evaluates a flake from the git INDEX, not the working tree. An untracked
# file is simply invisible, and the error that causes ("path does not exist")
# points at a symptom nowhere near the cause. Warn loudly rather than donate an
# hour to it.
untracked="$(git ls-files --others --exclude-standard)"
if [ -n "$untracked" ]; then
  echo "!! WARNING: untracked files — nix will NOT see these:" >&2
  printf '!!   %s\n' $untracked >&2
  echo "!! Run 'git add' before trusting a green result below." >&2
  echo >&2
fi

# stderr is deliberately NOT captured. Nix emits `warnings` — including the
# hardware-configuration.nix placeholder sentinel — as evaluation traces on
# stderr, and an earlier version of this script swallowed them on success. A
# gate that hides the one warning it exists to surface is worse than no gate.
# Traces therefore print inline, above the result line for the host that
# produced them; the marker below keeps that attribution unambiguous.
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
