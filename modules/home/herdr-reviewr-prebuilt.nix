{
  lib,
  stdenvNoCC,
  fetchurl,
  system,
  manifestSrc,
}:
# reviewr (persiyanov/herdr-reviewr) from upstream's prebuilt release tarballs,
# assembled into the plugin directory `herdr plugin link` points at. herdr
# links by reference, so this store path IS the plugin: a version bump yields a
# new path and the activation in herdr.nix re-points at it (link is idempotent
# and re-points on path change — verified against 0.9.5 before packaging).
#
# The musl builds are fully static: no loader, nothing to patch — same policy
# as herdr-prebuilt.nix, and dontStrip/dontPatchELF keep the bytes identical to
# the release asset. The plugin runs with full user privileges (no plugin
# sandboxing in herdr v1), so the pin plus the vendored manifest
# (config/herdr/plugins/reviewr-herdr-plugin.toml, re-fetched by nfb in
# lockstep with the tarball) are the review surface.
#
# Trust trade-off, accepted like herdr's own: the hash pins the exact bytes,
# but nobody re-derives them. No from-source fallback exists — the plugin has
# no flake input by design (nothing binds one); the pin in tool-pins.json is
# the only record.
let
  pins = (builtins.fromJSON (builtins.readFile ./tool-pins.json))."herdr-reviewr";
  version = pins.version;
  srcs = {
    x86_64-linux = {
      url = "https://github.com/persiyanov/herdr-reviewr/releases/download/v${version}/herdr-reviewr-x86_64-unknown-linux-musl.tar.gz";
      hash = pins."x86_64-linux";
    };
    aarch64-linux = {
      url = "https://github.com/persiyanov/herdr-reviewr/releases/download/v${version}/herdr-reviewr-aarch64-unknown-linux-musl.tar.gz";
      hash = pins."aarch64-linux";
    };
  };
  src = srcs.${system} or (throw "herdr-reviewr-prebuilt: unsupported system ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "herdr-reviewr-plugin";
  inherit version;

  src = fetchurl {
    inherit (src) url;
    inherit (src) hash;
  };

  # The tarball has no top-level directory — the binary sits at its root.
  sourceRoot = ".";

  dontStrip = true;
  dontPatchELF = true;

  # The tarball carries the bare static binary at its root; the manifest is the
  # vendored asset, deployed unchanged — herdr validates it at link time, so a
  # drift between pin and manifest fails the rebuild, not the session.
  installPhase = ''
    runHook preInstall
    install -Dm755 herdr-reviewr "$out/bin/herdr-reviewr"
    install -Dm644 "${manifestSrc}" "$out/herdr-plugin.toml"
    runHook postInstall
  '';

  meta = {
    description = "reviewr herdr plugin (upstream prebuilt binary + vendored manifest)";
    homepage = "https://github.com/persiyanov/herdr-reviewr";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
