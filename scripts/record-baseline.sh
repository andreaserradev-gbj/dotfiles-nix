#!/usr/bin/env bash
# record-baseline.sh — re-record scripts/drvpath-baseline after an INPUT BUMP.
#
# A bump moves whichever hosts that input reaches; the move is intended by
# construction, so it is not the "name the move" decision the gate exists to
# force. This records it instead: evaluate through
# check-hosts.sh --update-baseline (which refuses on an eval failure and prints
# each host's old -> new drvPath), then stage the file with the bump it belongs
# to, so `git diff HEAD` reviews one change.
#
# Whatever the tree evaluates to is what gets recorded. Commit the bump as a
# whole: a baseline staged against work that stays out of the commit fails CI's
# evaluate job, which is the loud outcome, not a silent one.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$repo_root/scripts/check-hosts.sh" --update-baseline
git -C "$repo_root" add -- scripts/drvpath-baseline
