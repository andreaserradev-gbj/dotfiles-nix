{
  lib,
  stdenvNoCC,
  fetchurl,
  system,
}:
# omp (oh-my-pi) from upstream's prebuilt release binaries instead of the flake's
# from-source build: that build takes ~31 min on a fast CI runner, no binary cache
# anywhere carries it, and it re-triggers on EVERY `nfu` that moves
# nixpkgs-unstable (the omp flake input follows that tree). The full adoption
# record and the release-binary verification are in doc/omp.md.
#
# LOAD-BEARING: do NOT add autoPatchelfHook (or strip/patchelf of any kind). omp
# is a Bun standalone executable that locates its embedded JS payload via an
# absolute trailer ("---- Bun! ----") near the end of the file; autoPatchelfHook
# rewrites the interpreter string, shifts the section header table, and
# invalidates those offsets — the binary then silently degrades to a plain `bun`
# runtime. The stock /lib64 loader works only because NixOS's nix-ld provides it
# (modules/nixos/dev.nix); this derivation does not make the binary run on a
# NixOS without nix-ld. The glibc (not musl) asset is used: musl would add
# libstdc++/libgcc NEEDEDs that stock NixOS does not ship.
#
# Trust trade-off: the hash pins the exact bytes (fixed-output derivation), but
# nobody re-derives them; the from-source fallback is one attribute away
# (omp.nix). `nfb` (scripts/nfb.sh) bumps version + hashes in tool-pins.json and
# re-locks the matching flake input, so pin and module cannot disagree. Full
# trade-offs: doc/omp.md.
let
  pins = (builtins.fromJSON (builtins.readFile ./tool-pins.json)).omp;
  version = pins.version;
  srcs = {
    x86_64-linux = {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-linux-x64";
      hash = pins."x86_64-linux";
    };
    aarch64-linux = {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-linux-arm64";
      hash = pins."aarch64-linux";
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

  # fetchurl yields the bare ELF and install copies it byte-for-byte; nothing may
  # rewrite it (LOAD-BEARING above).
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
