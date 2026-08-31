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

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Nix evaluates a flake from the git INDEX, not the working tree. An untracked
# file is simply invisible, and the error that causes ("path does not exist")
# points at a symptom nowhere near the cause. Warn loudly rather than donate an
# hour to it.
#
# `git ls-files -z` + a NUL-delimited read loop, not word splitting on the
# whole blob: an unquoted $untracked in printf would split a path containing a
# space into two bogus filenames and glob-expand any path holding * or ?.
if [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo "!! WARNING: untracked files — nix will NOT see these:" >&2
  while IFS= read -r -d '' f; do
    printf '!!   %s\n' "$f" >&2
  done < <(git ls-files --others --exclude-standard -z)
  echo "!! Run 'git add' before trusting a green result below." >&2
  echo >&2
fi

# The host list is DERIVED from the flake, not restated here. A hardcoded list
# is a second source of truth that silently stops covering a host the moment
# one is added to flake.nix — which is exactly the invisible-until-you-build-it
# failure this script exists to prevent. Costs one extra eval of the flake's
# top level; the per-host evals below dominate anyway.
HOSTS="$(nix eval --raw .#nixosConfigurations \
  --apply 'cs: builtins.concatStringsSep " " (builtins.attrNames cs)')"
if [ -z "$HOSTS" ]; then
  echo "!! No nixosConfigurations found in the flake." >&2
  exit 1
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
