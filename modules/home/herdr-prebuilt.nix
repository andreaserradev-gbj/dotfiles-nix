{
  lib,
  stdenvNoCC,
  fetchurl,
  system,
}:
# herdr from upstream's prebuilt release binaries instead of the flake's
# from-source build. WHY THIS EXISTS: the from-source build measures ~5 min
# of herdr buildPhase on a fast CI runner (~6 min with its rust toolchain
# unpack + zig cache), it rebuilt on EVERY CI run because runner stores do
# not persist (the drv was byte-identical across PRs #25 and #26 — it
# recompiled anyway), and it re-triggered on every nfu that moved
# nixpkgs-unstable. The release binaries are what upstream's own install path
# ships; verified live on NixOS at v0.9.1: `herdr --version` and
# `herdr config check` both pass.
#
# LOAD-BEARING: the binary is STATIC-PIE (zero NEEDED libs — no glibc, no
# nix-ld, no libgcc). It must never be ELF-patched or stripped: there is
# nothing to patch and nothing to gain; the derivation sets
# dontStrip/dontPatchELF so the bytes stay byte-identical to the release
# asset (verified by cmp at adoption). This is SIMPLER than omp-prebuilt:
# no loader override at all, and no Bun-standalone trailer trap.
#
# The vendored plugin/extension assets (config/opencode/plugins/,
# config/omp/) are TEXT vendored in this repo and deployed by herdr.nix —
# they never depended on the source build, so dropping the build removes
# only the binary+toolchain from the closure (nvd-verified: herdr + zig
# cache + cargo vendor leave, ~-60 paths).
#
# TRADEOFFS (accepted, documented in doc/herdr.md):
# - Trust boundary widens from "herdr's build recipe" to "upstream's
#   release CI" — the hash pins the exact bytes (fixed-output derivation),
#   but nobody re-derives them. Mitigations: tag-pinned, SHA256 enforced by
#   FOD; the from-source fallback is one line away (see herdr.nix).
# - Not a Nix build: no grafts against our nixpkgs; the ONLY store output
#   is the unpacked binary.
#
# Update procedure (per herdr tag bump): run `nfb` (scripts/nfb.sh) — it bumps
# the version and both hashes in modules/home/tool-pins.json and re-fetches the
# two vendored agent assets from the new tag in one step, so pin, binary and
# assets can never disagree. No compile.
let
  # Version + both hashes come from modules/home/tool-pins.json — the single
  # source of the pin (herdr has no flake input). Written only by `nfb`
  # (scripts/nfb.sh).
  pins = (builtins.fromJSON (builtins.readFile ./tool-pins.json)).herdr;
  version = pins.version;
  srcs = {
    x86_64-linux = {
      url = "https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-linux-x86_64";
      hash = pins."x86_64-linux";
    };
    aarch64-linux = {
      url = "https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-linux-aarch64";
      hash = pins."aarch64-linux";
    };
  };
  src = srcs.${system} or (throw "herdr-prebuilt: unsupported system ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "herdr-prebuilt";
  inherit version;

  src = fetchurl {
    inherit (src) url;
    inherit (src) hash;
  };

  # No unpack/build phases: fetchurl yields the bare static-PIE ELF; install
  # copies it byte-for-byte. Nothing may rewrite the binary — see the
  # LOAD-BEARING note above.
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;
  noAuditTmpdir = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/herdr"
    runHook postInstall
  '';

  meta = {
    description = "herdr terminal workspace manager (upstream prebuilt binary)";
    homepage = "https://herdr.dev";
    license = lib.licenses.asl20;
    mainProgram = "herdr";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
