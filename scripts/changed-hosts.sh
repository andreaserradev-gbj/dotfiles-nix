#!/usr/bin/env bash
# changed-hosts.sh — print, as a JSON array, the hosts whose system drvPath
# differs from the last commit CI actually built (baseline defaults to `verified`).
# The build-skipping gate: an identical drvPath is the SAME derivation, already
# built green, so rebuilding it proves nothing. See doc/workflow.md, section CI.
# Usage: changed-hosts.sh [baseline-ref] [host...]
set -euo pipefail

BASELINE_REF="${1:-verified}"
shift || true
ALLOWED="$*"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Ask the flake, never a hardcoded list — the rule check-hosts.sh states.
HOSTS="$(nix eval --raw .#nixosConfigurations \
  --apply 'cs: builtins.concatStringsSep " " (builtins.attrNames cs)')"
if [ -z "$HOSTS" ]; then
  echo "!! No nixosConfigurations found in the flake." >&2
  exit 1
fi

# Naming hosts restricts the answer to that set (CI passes the hosts it builds, so
# the "what does CI build" policy stays in ci.yml); with none, all are considered.
#
# Fail loudly on a name the flake does not define — a typo in ci.yml's matrix
# would otherwise silently build nothing.
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
# checkout: its drvPath must be evaluated against the flake.lock that commit
# shipped — a lock bump legitimately moves every host, and evaluating the old
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
    # A failing baseline eval is not an error — there is then no prior build to
    # lean on, so the host must be built. Its stderr is printed rather than
    # discarded: only that distinguishes "host absent on the baseline" from a
    # broken eval (no network, GitHub rate limit).
    base_err="$(mktemp)"
    if base="$(nix eval --raw "github:${slug}/${baseline_sha}#${attr}" 2>"$base_err")"; then
      rm -f "$base_err"
      if [ "$cur" = "$base" ]; then
        echo "   ${host}: unchanged — already built on ${BASELINE_REF}" >&2
        continue
      fi
      echo "   ${host}: MOVED" >&2
      echo "     was ${base}" >&2
      echo "     now ${cur}" >&2
    else
      echo "   ${host}: no baseline drvPath — building" >&2
      sed 's/^/     /' "$base_err" >&2
      rm -f "$base_err"
    fi
    changed="${changed} ${host}"
  done
fi

# Emit a JSON array for the Actions matrix on STDOUT; all reasoning above goes to
# stderr so the two never mix. No `jq` needed (it is not in the devShell): host
# names are flake attribute names, so they cannot contain a quote or backslash.
out=""
for host in $changed; do
  out="${out}${out:+,}\"${host}\""
done
printf '[%s]\n' "$out"
