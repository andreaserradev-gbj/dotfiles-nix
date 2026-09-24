{
  lib,
  stdenvNoCC,
  fetchurl,
  system,
}:
# herdr from upstream's prebuilt release binaries instead of the flake's
# from-source build: that build measures ~5 min of buildPhase on a fast CI runner
# (plus its rust toolchain unpack and zig cache) and rebuilt on every CI run
# because runner stores do not persist — the drv was byte-identical across two
# PRs. Numbers and the adoption record: doc/herdr.md.
#
# LOAD-BEARING: the binary is static-PIE — zero NEEDED libraries, nothing to
# patch — so dontStrip/dontPatchELF keep it byte-identical to the release asset.
# Do not add patchelf or a loader override: unlike omp-prebuilt there is no
# nix-ld dependency and no Bun-standalone trailer trap.
#
# The vendored plugin/extension assets (config/opencode/plugins/, config/omp/)
# are text in this repo, deployed by herdr.nix, and never depended on the source
# build — dropping the build removes only the binary + toolchain from the closure
# (nvd-verified: herdr, the zig cache and the cargo vendor leave).
#
# Trust trade-off: the hash pins the exact bytes (fixed-output derivation), but
# nobody re-derives them; the from-source fallback is one line away (herdr.nix).
# `nfb` (scripts/nfb.sh) bumps version + hashes and re-fetches the vendored assets
# in one step, so pin, binary and assets cannot disagree. Full trade-offs:
# doc/herdr.md.
let
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

  # fetchurl yields the bare static-PIE ELF and install copies it byte-for-byte;
  # nothing may rewrite it (LOAD-BEARING above).
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
