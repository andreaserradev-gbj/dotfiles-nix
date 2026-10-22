#!/usr/bin/env bash
# check-hosts.sh — evaluate EVERY host and print its system drvPath. This is the
# multi-host regression gate: `nix flake check` does not evaluate
# nixosConfigurations at all, so a typo in the host you are NOT sitting on stays
# invisible until the day you build it. Evaluation is architecture-independent,
# so the x86_64 hosts are checked from an aarch64 VM and vice versa.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Nix evaluates only git-TRACKED paths — a tracked file's working-tree edits
# (staged or not) are seen, an untracked one is simply not there, so evaluation
# fails with "Path 'X' … is not tracked by Git" — loud, but only if you get that
# far. Warn before the run, not after: a green result on a stale tree is worse
# than a red one. The `-z` + NUL-delimited read loop below keeps a path holding a
# space or a `*` from splitting into bogus filenames.
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

# The drvPath doubles as the reference hash around any change: record it before,
# compare after — a host you did not mean to touch must not move (doc/workflow.md).
#
# The comparison is MECHANICAL: scripts/drvpath-baseline records every host's
# drvPath, and a host that moved while its baseline line did not fails this
# gate — the repo rule "a move you cannot name is the failure", enforced.
# `--update-baseline` re-records a deliberate move; the reason belongs in the
# commit message next to the baseline change, not in this script.
baseline_file="$repo_root/scripts/drvpath-baseline"
update=0
[ "${1:-}" = "--update-baseline" ] && update=1

# stderr is deliberately NOT captured: Nix emits `warnings` as evaluation traces
# there, and hiding them would remove the diagnostics this gate exists to surface.
status=0
current="$(mktemp)"
trap 'rm -f "$current"' EXIT
for host in $HOSTS; do
  echo "-- evaluating ${host}"
  if drv="$(nix eval --raw ".#nixosConfigurations.${host}.config.system.build.toplevel.drvPath")"; then
    printf '%s %s\n' "$host" "$drv" >> "$current"
    printf '%-8s %s\n' "$host" "$drv"
  else
    printf '%-8s EVAL FAILED\n' "$host"
    status=1
  fi
done

if [ "$update" = 1 ]; then
  # A baseline written from a partial evaluation would silently STOP COVERING
  # the hosts that failed: their lines are absent, so the next run sees nothing
  # to compare. Refuse instead — an eval failure is the one thing this gate
  # exists to catch, and it must not be able to erase itself from the record.
  if [ "$status" != 0 ]; then
    echo "!! baseline NOT updated: a host failed to evaluate (see above)." >&2
    exit 1
  fi
  # Report what the record is about to say, so the diff is reviewable at the
  # terminal too and not only in `git diff`.
  if [ -f "$baseline_file" ]; then
    while read -r host recorded; do
      now="$(awk -v h="$host" '$1 == h { print $2 }' "$current")"
      if [ -z "$now" ]; then
        printf '   %s: dropped (no longer in the flake)\n' "$host"
      elif [ "$now" != "$recorded" ]; then
        printf '   %s: %s -> %s\n' "$host" "$recorded" "$now"
      fi
    done < "$baseline_file"
    while read -r host drv; do
      awk -v h="$host" '$1 == h { found = 1 } END { exit !found }' "$baseline_file" ||
        printf '   %s: new -> %s\n' "$host" "$drv"
    done < "$current"
  fi
  mv "$current" "$baseline_file"
  trap - EXIT
  echo "baseline updated: $baseline_file"
  exit "$status"
fi

# A missing baseline file is a loud setup error, not a pass.
if [ ! -f "$baseline_file" ]; then
  echo "!! $baseline_file is missing — run '$0 --update-baseline' once and commit it." >&2
  exit 1
fi

# Compare: every recorded host must still exist, and every drvPath must match —
# an unnamed move fails here, naming both paths.
while read -r host recorded; do
  now="$(awk -v h="$host" '$1 == h { print $2 }' "$current")"
  if [ -z "$now" ]; then
    echo "!! ${host}: in the baseline but not in the flake — stale baseline entry." >&2
    status=1
  elif [ "$now" != "$recorded" ]; then
    echo "!! ${host} moved:" >&2
    echo "!!   recorded: $recorded" >&2
    echo "!!   current:  $now" >&2
    echo "!! A move you cannot name is the failure. If this move is named, update" >&2
    echo "!! $baseline_file in the same change (or run '$0 --update-baseline')." >&2
    status=1
  fi
done < "$baseline_file"

exit "$status"

