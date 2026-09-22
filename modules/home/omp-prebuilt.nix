{
  lib,
  stdenvNoCC,
  fetchurl,
  system,
}:
# omp (oh-my-pi) from upstream's prebuilt release binaries instead of the
# flake's from-source build. WHY THIS EXISTS: the from-source build takes
# ~31 min on a fast CI runner (no binary cache anywhere carries it — see
# doc/omp.md), the full cycle exceeds an hour locally, and it re-triggers on
# EVERY nfu that moves nixpkgs-unstable (the omp flake input follows that
# tree). The release binaries are what upstream's own install script and
# Homebrew ship; verified live on NixOS at v18.2.8: `omp --version`, a live
# model call through the local ollama daemon, and `omp completions zsh` all
# work with the stock /lib64 loader — the binary needs NOTHING beyond
# glibc's own libraries (NEEDED: libc/pthread/dl/m).
#
# LOAD-BEARING: do NOT add autoPatchelfHook (or strip/patchelf of any kind).
# omp is a Bun standalone executable — it locates its embedded JS payload
# via an absolute trailer ("---- Bun! ----") near the end of the file.
# autoPatchelfHook rewrites the interpreter string and shifts the section
# header table (+144 bytes at v18.2.7), which invalidates those absolute
# offsets: the binary silently degrades to a plain `bun` runtime
# (`omp --version` prints "Bun v1.4.2", completions say "#compdef bun").
# Verified experimentally 2026-09-21. The stock loader path works because
# /lib64/ld-linux-x86-64.so.2 is provided by NixOS's nix-ld on dev hosts
# (modules/nixos/dev.nix) — this derivation does NOT make the binary work
# on a stock NixOS without nix-ld.
#
# TRADEOFFS (accepted, documented in doc/omp.md):
# - Trust boundary widens from "omp's flake build recipe" to "upstream's
#   release CI" — the hash pins the exact bytes (fixed-output derivation),
#   but nobody re-derives them. Mitigations: MIT-licensed upstream,
#   tag-pinned, SHA256 enforced by FOD; the from-source fallback is one
#   attribute away (see omp.nix).
# - Not a Nix build: no grafts against our nixpkgs, no per-host rebuild of
#   the binary itself; the ONLY store output is the unpacked binary.
# - The glibc (not musl) variant is used: musl would add libstdc++/libgcc
#   NEEDEDs that stock NixOS does not ship, per upstream's own Alpine note.
#
# Update procedure: bump BOTH the version here and the omp flake input's
# ?ref= in flake.nix (they must agree — omp.nix's settings are written for
# a specific compiled-in CURRENT_SETUP_VERSION), re-hash, done. No compile.
let
  version = "18.2.8";
  srcs = {
    x86_64-linux = {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-linux-x64";
      hash = "sha256-sMAdpzOdh/1dJtf6p7YcExpQZIOZlieDiZ/ZOm2LHWU=";
    };
    aarch64-linux = {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-linux-arm64";
      hash = "sha256-qapj5DyVzKoGg+n+0DRjxAGCniIK0rvEFLNB0tSeWAY=";
    };
  };
  src = srcs.${system} or (throw "omp-prebuilt: unsupported system ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "omp-prebuilt";
  inherit version;

  src = fetchurl {
    inherit (src) url;
    inherit (src) hash;
  };

  # No unpack/build phases: fetchurl yields the bare ELF; install copies it
  # byte-for-byte (install, not cp, to keep 755 + no stray modes). Nothing
  # may rewrite the ELF — see the LOAD-BEARING note above.
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;
  noAuditTmpdir = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/omp"
    runHook postInstall
  '';

  meta = {
    description = "oh-my-pi coding agent (upstream prebuilt binary)";
    homepage = "https://omp.sh";
    license = lib.licenses.mit;
    mainProgram = "omp";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
