#!/usr/bin/env bash
# changed-hosts.sh — print, as a JSON array, the hosts whose system drvPath
# differs from the last commit CI actually built.
#
# This is the build-skipping gate. A host whose drvPath is byte-identical to
# one on the baseline is not "probably fine": it is the SAME derivation, and
# that derivation already built green. Re-downloading its closure onto a fresh
# runner proves nothing and costs ~6 minutes for geekom alone.
#
# The baseline is `verified`, not `main`: `verified` is by construction the
# last commit whose whole build matrix passed, whereas `main` may hold a commit
# whose build is still running or has failed. Comparing against `main` could
# therefore skip a build on the strength of a build that never succeeded.
#
# A doc- or CI-only change moves no host, prints [], and skips the build matrix
# entirely. A flake.lock bump moves every host and skips nothing — correct in
# both directions, and derived rather than guessed.
#
# Usage: changed-hosts.sh [baseline-ref] [host...]
#
# Naming hosts restricts the answer to that set. CI passes the hosts it is
# willing to build, so the "which hosts does CI build" policy stays in ci.yml
# next to the comment explaining it, rather than being restated here. With no
# host arguments every host in the flake is considered.
#
# Output: a JSON array on stdout, for a GitHub Actions matrix. Human-readable
# reasoning goes to stderr so the two never mix.
set -euo pipefail

BASELINE_REF="${1:-verified}"
shift || true
ALLOWED="$*"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Same derivation-not-restatement rule as check-hosts.sh: ask the flake.
HOSTS="$(nix eval --raw .#nixosConfigurations \
  --apply 'cs: builtins.concatStringsSep " " (builtins.attrNames cs)')"
if [ -z "$HOSTS" ]; then
  echo "!! No nixosConfigurations found in the flake." >&2
  exit 1
fi

# Intersect with the caller's set, and fail loudly on a name the flake does not
# define — a typo in ci.yml's matrix would otherwise silently build nothing.
if [ -n "$ALLOWED" ]; then
  for want in $ALLOWED; do
    case " $HOSTS " in
      *" $want "*) ;;
      *)
        echo "!! Requested host '$want' is not in the flake (have: $HOSTS)" >&2
        exit 1
        ;;
    esac
  done
  HOSTS="$ALLOWED"
fi

# The baseline is fetched as a flake by REVISION, not read from the local
# checkout, because its drvPath must be evaluated against the flake.lock that
# commit shipped. A lock bump legitimately moves every host; evaluating the old
# tree with the new lock would hide exactly that.
slug="${GITHUB_REPOSITORY:-}"
if [ -z "$slug" ]; then
  slug="$(git remote get-url origin 2>/dev/null |
    sed -E 's#^(git@[^:]+:|https://[^/]+/)##; s#\.git$##')"
fi

baseline_sha="$(git ls-remote origin "refs/heads/${BASELINE_REF}" 2>/dev/null | cut -f1)"

changed=""
if [ -z "$baseline_sha" ]; then
  echo "-- no '${BASELINE_REF}' branch on origin — nothing has been verified yet;" >&2
  echo "   building every host." >&2
  changed="$HOSTS"
else
  echo "-- baseline: ${BASELINE_REF} @ ${baseline_sha}" >&2
  for host in $HOSTS; do
    attr="nixosConfigurations.${host}.config.system.build.toplevel.drvPath"
    cur="$(nix eval --raw ".#${attr}")"
    # A host absent from the baseline (newly added) fails to evaluate there.
    # That is not an error: it means there is no prior build to lean on, so it
    # must be built.
    if base="$(nix eval --raw "github:${slug}/${baseline_sha}#${attr}" 2>/dev/null)"; then
      if [ "$cur" = "$base" ]; then
        echo "   ${host}: unchanged — already built on ${BASELINE_REF}" >&2
        continue
      fi
      echo "   ${host}: MOVED" >&2
      echo "     was ${base}" >&2
      echo "     now ${cur}" >&2
    else
      echo "   ${host}: not present on ${BASELINE_REF} — never built" >&2
    fi
    changed="${changed} ${host}"
  done
fi

# Emit a JSON array. `jq` is not in the devShell and this needs no dependency:
# host names are flake attribute names, so they cannot contain a quote or a
# backslash and need no escaping.
out=""
for host in $changed; do
  out="${out}${out:+,}\"${host}\""
done
printf '[%s]\n' "$out"
