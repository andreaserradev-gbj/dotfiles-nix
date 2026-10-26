#!/usr/bin/env bash
# nfb.sh — bump the pinned upstream tool tags (omp, herdr, herdr-reviewr, ovis)
# to their latest release: modules/home/tool-pins.json (version + both per-arch
# hashes), the matching `?ref=` in flake.nix for the tools that have a flake
# input, each tool's vendored assets, then re-lock just those inputs. TTY-interactive by design
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
nfb — bump the pinned tool tags (omp, herdr, herdr-reviewr, ovis) to their
latest upstream release.

usage: nfb.sh [--help] [--verify-ovis-hashes]

For each tool in turn: reports whether a newer release exists and, on a TTY,
asks before writing. A bump updates modules/home/tool-pins.json (version + both
per-arch hashes), re-vendors each tool's vendored assets (herdr's two agent
assets, reviewr's plugin manifest, ovis's plugin manifest), and — for the tools
with a flake input (omp) — rewrites the `?ref=` in flake.nix and re-locks that
input. Without a TTY it only reports.

ovis is the one source build: besides the two PTY-host assets it records the
source tree's hash and two dependency trees per arch, which costs a bun install
per arch. Its vendored manifest is rewritten by the derivation, so the copy in
config/ovis/ stays the pristine upstream file.

--verify-ovis-hashes re-measures ovis's four committed hashes and compares them
with tool-pins.json, then exits: no API call, no prompt, no write. The bump path
reaches that measurement only when a newer tag exists and the user answers y, so
this is the only non-interactive way to re-check the invariant.
EOF
}

verify_ovis=0
case "${1:-}" in
  --help | -h)
    usage
    exit 0
    ;;
  # Re-measure ovis's committed hashes without a release. The bump path reaches
  # ovis_dep_hashes only after a newer tag prompts `y`, so this is the only way
  # to re-check that the pins are the trees the FODs produce.
  --verify-ovis-hashes) verify_ovis=1 ;;
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
tools=(omp herdr herdr-reviewr ovis)
declare -A slug=(
  [omp]=can1357/oh-my-pi
  [herdr]=herdrdev/herdr
  [herdr-reviewr]=persiyanov/herdr-reviewr
  [ovis]=devswha/ovis
)
declare -A asset=(
  [omp:x86_64-linux]=omp-linux-x64
  [omp:aarch64-linux]=omp-linux-arm64
  [herdr:x86_64-linux]=herdr-linux-x86_64
  [herdr:aarch64-linux]=herdr-linux-aarch64
  [herdr-reviewr:x86_64-linux]=herdr-reviewr-x86_64-unknown-linux-musl.tar.gz
  [herdr-reviewr:aarch64-linux]=herdr-reviewr-aarch64-unknown-linux-musl.tar.gz
  [ovis:x86_64-linux]=ovis-pty-sidecar-linux-x64
  [ovis:aarch64-linux]=ovis-pty-sidecar-linux-arm64
)
# The subset of tools that also have a flake input whose `?ref=` this script owns.
# herdr is absent by design: its input was removed (nothing bound it — the package
# is the prebuilt FOD), so its pin lives only in tool-pins.json and
# rewrite_ref/relock have nothing to touch for it.
declare -A flake_input=([omp]=1)
systems=(x86_64-linux aarch64-linux)

# Vendored assets, in lockstep with each tool's binary: upstream path at the
# tag -> this repo's copy -> a guard regex the fetched file must match (catches
# an upstream path/format change before it is vendored) and a marker regex
# whose matched line is reported old -> new on re-vendor. Tools without
# vendored assets simply declare no <tool>_asset_* arrays.
herdr_asset_up=(src/integration/assets/omp/herdr-agent-state.ts)
herdr_asset_dest=(config/omp/herdr-omp-agent-state.ts)
herdr_asset_guard=('^// HERDR_INTEGRATION_ID=omp$')
herdr_asset_marker=('^// HERDR_INTEGRATION_VERSION=')
reviewr_asset_up=(herdr-plugin.toml)
reviewr_asset_dest=(config/herdr/plugins/reviewr-herdr-plugin.toml)
reviewr_asset_guard=('^id = "persiyanov.reviewr"$')
reviewr_asset_marker=('^version = ')
# The pristine upstream manifest. The derivation rewrites the launcher commands
# on the way into the store, so this copy must stay byte-identical to the tag —
# rewriting it here too would hide an upstream change to that launcher.
ovis_asset_up=(herdr-plugin.toml)
ovis_asset_dest=(config/ovis/ovis-herdr-plugin.toml)
ovis_asset_guard=('^id = "devswha.ovis"$')
ovis_asset_marker=('^version = ')

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
# input (herdr). Staging is for the review surface, not visibility: nix reads a
# tracked file's working-tree edits either way, so the pin table and `?ref=` are
# added only to keep the bump one reviewable, committable set.
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

# tool_has_vendored_assets TOOL — true when that tool declares vendored assets.
tool_has_vendored_assets() {
  declare -p "${1}_asset_up" >/dev/null 2>&1
}

# fetch_vendored_assets TOOL TAG — fetch + validate each vendored asset to a
# temp file, appending the paths to the global tmp_assets. Nothing in the repo
# is written here, so a failure leaves the tool's bump wholly unwritten.
fetch_vendored_assets() {
  local -n ups="$1_asset_up" guards="$1_asset_guard"
  local tool="$1" tag="$2" i tmp
  for i in "${!ups[@]}"; do
    tmp="$(mktemp)"
    wget -qO "$tmp" "https://raw.githubusercontent.com/${slug[$tool]}/${tag}/${ups[$i]}" || {
      rm -f "$tmp"
      fail "$tool: cannot fetch ${ups[$i]} at ${tag} — nothing written"
    }
    grep -qE -- "${guards[$i]}" "$tmp" || {
      rm -f "$tmp"
      fail "$tool: ${ups[$i]} does not match guard ${guards[$i]} — nothing written"
    }
    tmp_assets+=("$tmp")
  done
}

# write_vendored_assets TOOL — copy the fetched temp files over the repo
# copies. The marker line is REPORTED, never the decision rule: a
# same-marker content change must still land, and it shows up in the git
# diff for review.
write_vendored_assets() {
  local -n ups="$1_asset_up" dests="$1_asset_dest" markers="$1_asset_marker"
  local i dest tmp old new
  for i in "${!ups[@]}"; do
    dest="${dests[$i]}"
    tmp="${tmp_assets[$i]}"
    if cmp -s "$tmp" "$dest"; then
      printf '   %s: unchanged\n' "$dest"
    else
      old="$(grep -m1E -- "${markers[$i]}" "$dest" || true)"
      new="$(grep -m1E -- "${markers[$i]}" "$tmp" || true)"
      cp "$tmp" "$dest"
      printf '   %s: re-vendored (%s -> %s)\n' "$dest" "${old:-<absent>}" "${new:-<absent>}"
    fi
    rm -f "$tmp"
  done
}

# ovis_dep_hashes TAG SYS — print the source hash, the dev-tree hash and the prod-tree
# hash for one system, in one `sha256-…` line each, space separated.
#
# The source hash comes from the GitHub archive, which `fetchFromGitHub` also
# uses: archive/refs/tags/<tag>.tar.gz and archive/<tag>.tar.gz yield the same
# tree (verified for v0.4.18), so this matches what the derivation will fetch.
#
# The two dependency trees are the FODs' outputs, so they are computed the way
# the FODs compute them: a `bun install` for the target arch with HOME and the
# cache inside a scratch dir. `--cpu` matters — the dev tree is per-arch (441 MiB
# vs 434 MiB, different bindings), while the prod allowlist is arch-independent
# and resolves identically for both. That is why both prod entries carry one
# value and nfb writes it twice rather than measuring twice.
ovis_dep_hashes() {
  local tag="$1" sys="$2" cpu tmp src src_tree dev prod bun
  case "$sys" in
    x86_64-linux) cpu=x64 ;;
    aarch64-linux) cpu=arm64 ;;
    *) fail "ovis: no bun target for $sys" ;;
  esac
  # bun from the flake's unstable tree, not PATH: it is not installed on the dev
  # hosts (the derivation supplies it), and a 1.3.x from PATH is rejected by
  # upstream's preflight. Resolved through the flake so this uses the same bun
  # the build will.
  bun="$(nix build --no-link --print-out-paths --impure --expr \
    "let f = builtins.getFlake \"path:$repo_root\"; in f.inputs.nixpkgs-unstable.legacyPackages.${host_system:-x86_64-linux}.bun" \
    2>/dev/null)/bin/bun"
  [ -x "$bun" ] || fail "ovis: cannot resolve bun from the flake — nothing written"

  tmp="$(mktemp -d)"
  if ! wget -qO "$tmp/src.tar.gz" "https://github.com/${slug[ovis]}/archive/${tag}.tar.gz"; then
    rm -rf "$tmp"
    fail "ovis: cannot fetch the source archive for ${tag} — nothing written"
  fi
  tar xzf "$tmp/src.tar.gz" -C "$tmp"
  src_tree="$tmp/ovis-${tag#v}"
  [ -d "$src_tree" ] || fail "ovis: ${tag} archive has no ovis-${tag#v} directory"
  src="$(nix hash path "$src_tree")" || fail "ovis: cannot hash the source tree for $tag"

  # HOME and the cache live in the scratch dir, exactly as in the FOD, so a
  # warm cache in the user's HOME cannot change the hash the FOD will produce.
  mkdir -p "$tmp/dev"
  cp "$src_tree"/{bun.lock,package.json} "$tmp/dev/"
  cp -r "$src_tree/patches" "$tmp/dev/"

  # dev: the whole lock, frozen. --ignore-scripts is enough here: no package in
  # the lock declares a lifecycle script (counted 0).
  #
  # Captured from a subshell's stdout, not assigned inside it: a subshell's
  # variables die with it.
  dev="$(cd "$tmp/dev" && HOME="$tmp/dev/.home" BUN_INSTALL_CACHE_DIR="$tmp/dev/.cache" \
    "$bun" install --frozen-lockfile --ignore-scripts --os=linux --cpu="$cpu" >/dev/null 2>&1 \
    && nix hash path node_modules)" ||
    fail "ovis: bun install (dev, $sys) failed — nothing written"

  # prod: the allowlist from config/ovis/runtime-deps.json, which the derivation
  # also reads. Not `--production`: that keeps every runtime dependency.
  mkdir -p "$tmp/prod"
  cp -r "$tmp/dev/patches" "$tmp/prod/"
  jq --slurpfile keep <(jq -c . "$repo_root/config/ovis/runtime-deps.json") \
    '($keep[0]) as $k
     | .dependencies |= with_entries(select(.key as $n | $k | index($n)))
     | del(.devDependencies, .patchedDependencies)' \
    "$src_tree/package.json" >"$tmp/prod/package.json" ||
    fail "ovis: cannot write the prod package.json for $sys"
  prod="$(cd "$tmp/prod" && HOME="$tmp/prod/.home" BUN_INSTALL_CACHE_DIR="$tmp/prod/.cache" \
    "$bun" install --ignore-scripts --os=linux --cpu="$cpu" >/dev/null 2>&1 \
    && nix hash path node_modules)" ||
    fail "ovis: bun install (prod, $sys) failed — nothing written"

  rm -rf "$tmp"
  printf '%s %s %s\n' "$src" "$dev" "$prod"
}

failed=0
applied=0

if [ "$verify_ovis" = 1 ]; then
  # The same four values a bump would write, against the committed ones. The
  # comparison is what makes this a check rather than a print: a mismatch means
  # the derivation would resolve a different tree than the pin records.
  vtag="v$(jq -r '.ovis.version' "$pins_file")"
  vx="$(ovis_dep_hashes "$vtag" x86_64-linux)" || exit 1
  read -r vsrc vdev_x86 vprod_x86 <<<"$vx"
  va="$(ovis_dep_hashes "$vtag" aarch64-linux)" || exit 1
  read -r vsrc_arm vdev_arm vprod_arm <<<"$va"

  mismatch=0
  expect() {
    local key="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then
      printf 'ok   %s\n' "$key"
    else
      printf 'FAIL %s\n       pinned %s\n       built  %s\n' "$key" "$want" "$got"
      mismatch=1
    fi
  }
  expect ovis.source "$vsrc" "$(jq -r '.ovis.source' "$pins_file")"
  expect 'ovis.nodeModulesDev.x86_64-linux' "$vdev_x86" "$(jq -r '.ovis.nodeModulesDev["x86_64-linux"]' "$pins_file")"
  expect 'ovis.nodeModulesDev.aarch64-linux' "$vdev_arm" "$(jq -r '.ovis.nodeModulesDev["aarch64-linux"]' "$pins_file")"
  expect 'ovis.nodeModulesProd.x86_64-linux' "$vprod_x86" "$(jq -r '.ovis.nodeModulesProd["x86_64-linux"]' "$pins_file")"
  expect 'ovis.nodeModulesProd.aarch64-linux' "$vprod_arm" "$(jq -r '.ovis.nodeModulesProd["aarch64-linux"]' "$pins_file")"
  # The two invariants the bump path asserts, re-checked here: the source FOD is
  # arch-independent, and the allowlist holds nothing platform-specific.
  expect 'source is arch-independent' "$vsrc_arm" "$vsrc"
  expect 'prod tree is arch-independent' "$vprod_arm" "$vprod_x86"
  exit "$mismatch"
fi

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

  # ---- ovis: four hashes per arch, not two asset hashes ----
  # Its pin carries the PTY-host asset (same shape as the others) plus the source
  # tree and the two dependency trees. Measured here because no FOD can be
  # resolved without the hash it would produce.
  ovis_pin=""
  if [ "$tool" = ovis ]; then
    # Both arches are measured from whatever host runs nfb: the FOD passes
    # `--cpu=<arch>` on either host, so an `--cpu=arm64` install here is the very
    # tree the FOD produces on aarch64. Measured, not assumed: the source hash
    # must not vary by arch, and the two must agree on it.
    ovis_x86="$(ovis_dep_hashes "$tag" x86_64-linux)" || fail "ovis: hashing x86_64 failed — nothing written"
    read -r ovis_src ovis_dev_x86 ovis_prod_x86 <<<"$ovis_x86"
    ovis_arm="$(ovis_dep_hashes "$tag" aarch64-linux)" || fail "ovis: hashing aarch64 failed — nothing written"
    read -r ovis_src_arm ovis_dev_arm ovis_prod_arm <<<"$ovis_arm"
    [ "$ovis_src" = "$ovis_src_arm" ] ||
      fail "ovis: source hash differs per arch ($ovis_src vs $ovis_src_arm) — the source FOD is arch-independent, so this is a bug"
    # The prod allowlist has no platform-specific package: it resolves to the
    # same tree for both arches (measured). Assert it rather than assume it.
    [ "$ovis_prod_x86" = "$ovis_prod_arm" ] ||
      fail "ovis: prod tree hash differs per arch ($ovis_prod_x86 vs $ovis_prod_arm) — runtime-deps.json gained a platform-specific package"
    ovis_pin="$ovis_src $ovis_dev_x86 $ovis_dev_arm $ovis_prod_x86"
  fi

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

  # ---- vendored assets: fetch + validate to temp files, still before any write ----
  tmp_assets=()
  if tool_has_vendored_assets "$tool"; then
    fetch_vendored_assets "$tool" "$tag"
  fi

  # ---- write the pin table, the input ref, then the assets ----
  tmp_pins="$(mktemp)"
  if [ "$tool" = ovis ]; then
    read -r ovis_src ovis_dev_x86 ovis_dev_arm ovis_prod <<<"$ovis_pin"
    jq --indent 2 \
      --arg v "$new" --arg src "$ovis_src" \
      --arg dx "$ovis_dev_x86" --arg da "$ovis_dev_arm" --arg pr "$ovis_prod" \
      --arg px "$sri_x86" --arg pa "$sri_arm" \
      '.[ovis].version = $v
       | .[ovis].source = $src
       | .[ovis].nodeModulesDev["x86_64-linux"] = $dx
       | .[ovis].nodeModulesDev["aarch64-linux"] = $da
       | .[ovis].nodeModulesProd["x86_64-linux"] = $pr
       | .[ovis].nodeModulesProd["aarch64-linux"] = $pr
       | .[ovis].ptyHost["x86_64-linux"] = $px
       | .[ovis].ptyHost["aarch64-linux"] = $pa' \
      "$pins_file" >"$tmp_pins"
  else
    jq --indent 2 \
      --arg t "$tool" --arg v "$new" --arg x "$sri_x86" --arg a "$sri_arm" \
      '.[$t].version = $v | .[$t]["x86_64-linux"] = $x | .[$t]["aarch64-linux"] = $a' \
      "$pins_file" >"$tmp_pins"
  fi
  mv "$tmp_pins" "$pins_file"

  rewrite_ref "$tool" "$tag"

  if tool_has_vendored_assets "$tool"; then
    write_vendored_assets "$tool"
  fi

  # ---- re-lock just this input (helper stages first) ----
  relock "$tool" "$tag"

  printf 'nfb: %s %s -> %s applied (pin file + flake.nix ref + flake.lock re-locked)\n' \
    "$tool" "$cur" "$new"
  applied=1
  git status --short
  if [ "$tool" = herdr ]; then
    printf '!! manual: npx skills add herdrdev/herdr --skill herdr -g   (the herdr skill is npx-managed, not vendored)\n'
  fi
done

# A bump is an intended move, so re-record the baseline here instead of leaving
# the user to notice the gate failing. The recorder stages it with the bump.
if [ "$applied" = 1 ] && [ "$failed" = 0 ]; then
  "$repo_root/scripts/record-baseline.sh" || failed=1
fi

printf 'next: git diff -> ./scripts/check-hosts.sh -> nrp -> PR per doc/workflow.md\n'
exit "$failed"
