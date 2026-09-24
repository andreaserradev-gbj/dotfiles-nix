#!/usr/bin/env bash
# nfb.sh — bump the pinned upstream tool tags (omp, herdr) to their latest
# release: modules/home/tool-pins.json (version + both per-arch hashes), the
# matching `?ref=` in flake.nix for the tools that have a flake input, herdr's two
# vendored agent assets, then re-lock just those inputs. TTY-interactive by design
# — the git diff is the review surface — and with no TTY it reports and writes
# nothing. It never runs the full `nix flake update`: that stays `nfu`'s job.
#
# The `?ref=` must stay a LITERAL in flake.nix, which is why this script rewrites
# it instead of Nix deriving it from tool-pins.json (owner of that rule: the omp
# input in flake.nix).
#
# Exit codes: 0 ran to completion (applied, declined, or nothing new);
#             1 a check or an apply failed, or a dependency is missing;
#             2 usage error.
set -euo pipefail

usage() {
  cat <<'EOF'
nfb — bump the pinned tool tags (omp, herdr) to their latest upstream release.

usage: nfb.sh [--help]

For each tool in turn: reports whether a newer release exists and, on a TTY,
asks before writing. A bump updates modules/home/tool-pins.json (version + both
per-arch hashes), re-vendors herdr's two agent assets, and — for the tools with
a flake input (omp) — rewrites the `?ref=` in flake.nix and re-locks that input.
Without a TTY it only reports.
EOF
}

case "${1:-}" in
  --help | -h)
    usage
    exit 0
    ;;
  "") ;;
  *)
    usage >&2
    exit 2
    ;;
esac

missing=""
for c in jq wget nix git cmp; do
  command -v "$c" >/dev/null 2>&1 || missing+=" $c"
done
if [ -n "$missing" ]; then
  printf 'nfb: missing dependencies:%s\n' "$missing" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
pins_file="modules/home/tool-pins.json"
flake_file="flake.nix"

[ -f "$pins_file" ] || {
  printf 'nfb: %s not found (run from a checkout of this repo)\n' "$pins_file" >&2
  exit 1
}

# Tool table. Order matters only for the prompts (omp first, the fast-moving one).
tools=(omp herdr)
declare -A slug=(
  [omp]=can1357/oh-my-pi
  [herdr]=herdrdev/herdr
)
declare -A asset=(
  [omp:x86_64-linux]=omp-linux-x64
  [omp:aarch64-linux]=omp-linux-arm64
  [herdr:x86_64-linux]=herdr-linux-x86_64
  [herdr:aarch64-linux]=herdr-linux-aarch64
)
# The subset of tools that also have a flake input whose `?ref=` this script owns.
# herdr is absent by design: its input was removed (nothing bound it — the package
# is the prebuilt FOD), so its pin lives only in tool-pins.json and
# rewrite_ref/relock have nothing to touch for it.
declare -A flake_input=([omp]=1)
systems=(x86_64-linux aarch64-linux)

# herdr's vendored agent assets, in lockstep with the binary: upstream path at the
# tag -> this repo's copy -> the HERDR_INTEGRATION_ID that file must declare (the
# guard that catches an upstream path/format change before it is vendored).
herdr_asset_up=(src/integration/assets/opencode/herdr-agent-state.js src/integration/assets/omp/herdr-agent-state.ts)
herdr_asset_dest=(config/opencode/plugins/herdr-agent-state.js config/omp/herdr-omp-agent-state.ts)
herdr_asset_id=(opencode omp)

case "$(uname -m)" in
  x86_64) host_system="x86_64-linux" ;;
  aarch64 | arm64) host_system="aarch64-linux" ;;
  *) host_system="" ;;
esac
if [ -z "$host_system" ]; then
  printf 'nfb: unknown architecture %s — hashes will not be cross-checked locally\n' "$(uname -m)" >&2
fi

# Any abort after a prompt means NOTHING is left half-written for that tool.
fail() {
  printf '!! %s\n' "$1" >&2
  exit 1
}

# rewrite_ref TOOL TAG — point the one input URL for that tool's repo at TAG.
# Skipped for a tool with no flake input (herdr). Anchored on the repo slug
# (unique in flake.nix) and asserted afterwards: a silent no-match would leave the
# pin table and the input ref disagreeing, which is the failure this exists to
# prevent.
rewrite_ref() {
  local tool="$1" tag="$2" n
  [ -n "${flake_input[$tool]:-}" ] || return 0
  local repo_slug="${slug[$tool]}"
  sed -i -E "s|(github:${repo_slug}\?ref=)v[^\"]*|\1${tag}|" "$flake_file"
  n="$(grep -c "github:${repo_slug}?ref=${tag}" "$flake_file" || true)"
  if [ "$n" != "1" ]; then
    fail "flake.nix: expected exactly one 'github:${repo_slug}?ref=${tag}' after the rewrite, found ${n}"
  fi
}

# relock TOOL TAG — re-resolve just that input, and only when the lock does not
# already name TAG (so a routine run is silent, and a run interrupted between the
# pin write and the lock heals itself next time). Skipped for a tool with no flake
# input (herdr). Staging first is load-bearing: flakes read the git INDEX, so the
# new pin table and `?ref=` must be added before `nix flake update` sees them.
relock() {
  local tool="$1" tag="$2" locked
  [ -n "${flake_input[$tool]:-}" ] || return 0
  locked="$(jq -r --arg t "$tool" '.nodes[$t].original.ref // empty' flake.lock)"
  if [ "$locked" = "$tag" ]; then
    return 0
  fi
  printf '   flake.lock: %s %s -> %s, re-locking\n' "$tool" "${locked:-<absent>}" "$tag"
  git add -- "$pins_file" "$flake_file"
  nix flake update --flake "$repo_root" "$tool"
  git add -- flake.lock
}

failed=0

for tool in "${tools[@]}"; do
  cur="$(jq -r --arg t "$tool" '.[$t].version' "$pins_file")"
  api="https://api.github.com/repos/${slug[$tool]}/releases/latest"

  rel="$(wget -qO- --timeout=30 --tries=2 "$api")" || {
    printf '!! %s: GitHub API request failed (%s)\n' "$tool" "$api" >&2
    failed=1
    continue
  }
  tag="$(jq -er '.tag_name' <<<"$rel")" || {
    printf '!! %s: release JSON carries no tag_name\n' "$tool" >&2
    failed=1
    continue
  }
  # The tag feeds the `sed -i -E "s|…|\1${tag}|"` replacement and the `grep`
  # assertion in rewrite_ref(); anything but vX.Y.Z could break out of either.
  # Non-fatal like the checks above, so the other tool is still checked.
  [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    printf '!! %s: release tag %s is not vX.Y.Z\n' "$tool" "$tag" >&2
    failed=1
    continue
  }
  new="${tag#v}"

  # String comparison, not semver ordering: unequal is offered, equal is current.
  # The prompt shows both values, so a retracted/odd tag is visible there.
  if [ "$new" = "$cur" ]; then
    printf '%s: v%s (current)\n' "$tool" "$new"
    relock "$tool" "$tag"
    continue
  fi

  if [ ! -t 0 ]; then
    printf '%s: %s -> %s available (not applied: no TTY)\n' "$tool" "$cur" "$new"
    continue
  fi

  printf 'bump %s %s -> %s ? [y/N] ' "$tool" "$cur" "$new"
  read -r reply || reply=""
  case "$reply" in
    [yY]*) ;;
    *)
      printf '%s: skipped\n' "$tool"
      continue
      ;;
  esac

  # ---- resolve + verify both hashes (no writes yet) ----
  sri_x86=""
  sri_arm=""
  for sys in "${systems[@]}"; do
    name="${asset[$tool:$sys]}"
    if [ -z "$(jq -r --arg n "$name" '[.assets[]|select(.name==$n)][0].name // empty' <<<"$rel")" ]; then
      fail "$tool: asset ${name} missing from ${tag} — nothing written"
    fi
    url="https://github.com/${slug[$tool]}/releases/download/${tag}/${name}"
    digest="$(jq -r --arg n "$name" '[.assets[]|select(.name==$n)][0].digest // empty' <<<"$rel")"
    if [ -n "$digest" ]; then
      h="$(nix hash convert --hash-algo sha256 --from base16 --to sri "${digest#sha256:}")"
    else
      printf '   no digest for %s; downloading to hash\n' "$name"
      h="$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash)"
    fi
    if [ "$sys" = "$host_system" ]; then
      fetched="$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash)"
      [ "$fetched" = "$h" ] ||
        fail "$tool: ${name} digest ${h} != downloaded ${fetched} — nothing written"
      printf '   %s: verified against the downloaded asset\n' "$sys"
    fi
    case "$sys" in
      x86_64-linux) sri_x86="$h" ;;
      aarch64-linux) sri_arm="$h" ;;
    esac
  done

  # ---- herdr: fetch + validate both assets to temp files, still before any write ----
  tmp_assets=()
  if [ "$tool" = herdr ]; then
    for i in "${!herdr_asset_up[@]}"; do
      up="${herdr_asset_up[$i]}"
      id="${herdr_asset_id[$i]}"
      tmp="$(mktemp)"
      wget -qO "$tmp" "https://raw.githubusercontent.com/${slug[herdr]}/${tag}/${up}" || {
        rm -f "$tmp"
        fail "herdr: cannot fetch ${up} at ${tag} — nothing written"
      }
      grep -q "^// HERDR_INTEGRATION_ID=${id}$" "$tmp" || {
        rm -f "$tmp"
        fail "herdr: ${up} does not declare ID ${id} — nothing written"
      }
      tmp_assets+=("$tmp")
    done
  fi

  # ---- write the pin table, the input ref, then the assets ----
  tmp_pins="$(mktemp)"
  jq --indent 2 \
    --arg t "$tool" --arg v "$new" --arg x "$sri_x86" --arg a "$sri_arm" \
    '.[$t].version = $v | .[$t]["x86_64-linux"] = $x | .[$t]["aarch64-linux"] = $a' \
    "$pins_file" >"$tmp_pins"
  mv "$tmp_pins" "$pins_file"

  rewrite_ref "$tool" "$tag"

  if [ "$tool" = herdr ]; then
    for i in "${!herdr_asset_up[@]}"; do
      dest="${herdr_asset_dest[$i]}"
      tmp="${tmp_assets[$i]}"
      # The marker is REPORTED, never the decision rule: a same-marker content
      # change must still land, and it shows up in the git diff for review.
      if cmp -s "$tmp" "$dest"; then
        printf '   %s: unchanged\n' "$dest"
      else
        old_marker="$(grep -m1 '^// HERDR_INTEGRATION_VERSION=' "$dest" | cut -d= -f2)"
        new_marker="$(grep -m1 '^// HERDR_INTEGRATION_VERSION=' "$tmp" | cut -d= -f2)"
        cp "$tmp" "$dest"
        printf '   %s: re-vendored (HERDR_INTEGRATION_VERSION %s -> %s)\n' \
          "$dest" "$old_marker" "$new_marker"
      fi
      rm -f "$tmp"
    done
  fi

  # ---- re-lock just this input (helper stages first) ----
  relock "$tool" "$tag"

  printf 'nfb: %s %s -> %s applied (pin file + flake.nix ref + flake.lock re-locked)\n' \
    "$tool" "$cur" "$new"
  git status --short
  if [ "$tool" = herdr ]; then
    printf '!! manual: npx skills add herdrdev/herdr --skill herdr -g   (the herdr skill is npx-managed, not vendored)\n'
  fi
done

printf 'next: git diff -> ./scripts/check-hosts.sh -> nrp -> PR per doc/workflow.md\n'
exit "$failed"
