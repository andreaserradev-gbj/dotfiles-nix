{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  bun,
  system,
}:
# Ovis (devswha/ovis) — the herdr web/phone client — built from the pinned tag
# into the plugin directory `herdr plugin link` points at. Same shape as
# herdr-reviewr-prebuilt.nix, but from source: upstream ships no server asset.
# The build shape, the two dependency trees and the three traps are in
# doc/ovis.md, "Build shape".
#
# Neither FOD output is a plugin root: they are bare dependency trees, so the
# recursive hash is the tree's own NAR (no extra `node_modules/` level), which
# is what tool-pins.json records.
let
  pins = (builtins.fromJSON (builtins.readFile ./tool-pins.json)).ovis;
  inherit (pins) version;

  # What the server and the plugin scripts resolve at run time, and nothing
  # else: server/push.ts imports web-push, server/skills/walk.ts jsonc-parser,
  # server/cmd.ts @sindresorhus/slugify, scripts/plugin.ts qrcode-generator.
  # `bun build` fails the build when the list drifts, and it names the missing
  # package and the importing file.
  #
  # @pierre/diffs is NOT here. The client imports it, but Vite bundles it into
  # dist/ (its themes and diff worker are chunks there), so the server never
  # resolves it; only server/repo-diff.test.ts does, and the gate proves its
  # absence is harmless (measured: the gate passes with it removed).
  #
  # Data, not a Nix list, because scripts/nfb.sh computes the prod FOD's hash
  # from the same allowlist; two copies would drift into a hash that matches no
  # tree. Keep it a flat JSON array of package names.
  runtimeDeps = builtins.fromJSON (builtins.readFile ../../config/ovis/runtime-deps.json);

  src = fetchFromGitHub {
    owner = "devswha";
    repo = "ovis";
    rev = "v${version}";
    hash = pins.source;
  };

  arch =
    {
      x86_64-linux = "x64";
      aarch64-linux = "arm64";
    }
    .${system} or (throw "ovis-prebuilt: unsupported system ${system}");

  # From the pin, like the source and both trees: `nfb` writes it, and a hash
  # nothing reads would make a bump look applied while the build fetched the
  # previous sidecar.
  ptyHostHash = pins.ptyHost.${system} or (throw "ovis-prebuilt: unsupported system ${system}");

  # Both trees are installed for the TARGET arch, never the builder's: `--os`
  # and `--cpu` make an aarch64 tree resolvable on an x86_64 host and vice
  # versa, so a host that cannot execute the other arch can still build it.
  # The pair is a no-op for a native install (measured: same hash with and
  # without the flags on x86_64).
  installDeps =
    {
      outputHash,
      production ? false,
    }:
    stdenvNoCC.mkDerivation {
      pname = "ovis-deps-${if production then "prod" else "dev"}";
      inherit version src;
      nativeBuildInputs = [ bun ];

      # The output IS the dependency tree; see the header for why the hash
      # covers the tree's own NAR.
      dontFixup = true;
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      inherit outputHash;

      buildPhase = ''
        runHook preBuild
      ''
      + lib.optionalString production ''
        # The allowlist, written as package.json rather than as an install flag:
        # `--production` keeps every runtime dependency, 302 MiB of it.
        ${lib.getExe bun} -e '
          const p = await Bun.file("package.json").json();
          const keep = ${builtins.toJSON runtimeDeps};
          p.dependencies = Object.fromEntries(keep.filter((k) => k in p.dependencies).map((k) => [k, p.dependencies[k]]));
          delete p.devDependencies;
          delete p.patchedDependencies;
          await Bun.write("package.json", JSON.stringify(p, null, 2) + "\n");
        '
      ''
      + ''
        # HOME and the cache live in the build dir: nothing outside it is
        # writable in the sandbox, and a warm cache in the builder's HOME would
        # make the output depend on the builder's machine.
        export HOME=$PWD/.home
        export BUN_INSTALL_CACHE_DIR=$PWD/.bun-cache
        mkdir -p "$HOME" "$BUN_INSTALL_CACHE_DIR"
        ${lib.getExe bun} install \
          ${lib.optionalString (!production) "--frozen-lockfile"} \
          --ignore-scripts \
          --os=linux --cpu=${arch}
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp -r node_modules/. "$out/"
        runHook postInstall
      '';
    };

  devTree = installDeps { outputHash = pins.nodeModulesDev.${system}; };
  prodTree = installDeps {
    outputHash = pins.nodeModulesProd.${system};
    production = true;
  };

  ptyHost = fetchurl {
    url = "https://github.com/devswha/ovis/releases/download/v${version}/ovis-pty-sidecar-linux-${arch}";
    hash = ptyHostHash;
  };

  # The vendored upstream manifest, re-fetched by nfb in lockstep with the pin.
  # Deploying this repo's copy rather than reading the source tree's is what
  # makes a pin/manifest disagreement a rebuild failure instead of a session
  # that links and misbehaves — the reviewr pattern. Its commands are rewritten
  # in installPhase.
  manifestSrc = ../../config/ovis/ovis-herdr-plugin.toml;
in
stdenvNoCC.mkDerivation {
  pname = "ovis-plugin";
  inherit version src;
  nativeBuildInputs = [ bun ];

  dontConfigure = true;
  dontStrip = true;

  buildPhase = ''
    runHook preBuild

    # The entry points: upstream's own table — ENTRIES, in server/entries.ts —
    # read rather than copied, so an entry it gains is gated with no edit here.
    # Both closure gates bundle this list; the shipped-files walk starts from it.
    entryList="$(${lib.getExe bun} -e '
      import { ENTRIES } from "./server/entries.ts";
      console.log(Object.values(ENTRIES).join("\n"));
    ')"
    mapfile -t entryPoints <<< "$entryList"
    if [ -z "''${entryPoints[0]:-}" ]; then
      echo "ovis: server/entries.ts lists no entry points" >&2
      exit 1
    fi

    # Vite writes node_modules/.cache and dist/, and a store input is
    # read-only, so the build runs in a writable copy.
    export HOME=$PWD/.home
    mkdir -p "$HOME"
    chmod -R u+w .
    cp -r ${devTree} node_modules
    chmod -R u+w node_modules

    # The files that ship, listed once for installPhase by
    # ovis-shipped-files.ts (its header says how they are found).
    "${lib.getExe bun}" run ${./ovis-shipped-files.ts} "$PWD" "''${entryPoints[@]}" > "$TMPDIR/shipped"
    if [ ! -s "$TMPDIR/shipped" ]; then
      echo "ovis: ovis-shipped-files.ts listed nothing" >&2
      exit 1
    fi

    # By path, not through node_modules/.bin. Both work on a writable tree
    # (measured); the path names no symlink, so it cannot become the thing that
    # breaks when the tree is not.
    ${lib.getExe bun} --bun node_modules/vite/bin/vite.js build

    # The shipping tree replaces the build tree BEFORE the gate: a gate run
    # against the dev tree resolves everything and can never fail.
    rm -rf node_modules
    cp -r ${prodTree} node_modules

    # Closure gate: bundle every entry point the manifest can launch, against
    # the tree that ships. A missing runtime package fails the build and names
    # itself. A grep over imports was the alternative, and it missed
    # qrcode-generator — reached through a script entry point, not server/.
    #
    # It runs here, over the PROD tree, and it gates packages only: a file the
    # installPhase forgot is invisible to it (Bun fails on a missing module in
    # the source tree too, which is why the same build is repeated against
    # $out at the end of installPhase).
    ${lib.getExe bun} build "''${entryPoints[@]}" \
      --target=bun --outdir="$TMPDIR/closure-gate"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"/{bin,scripts}

    # Every file the entry points load — the list buildPhase wrote — and what
    # is read without being a module.
    while IFS= read -r file; do
      install -Dm644 "$file" "$out/$file"
    done < "$TMPDIR/shipped"
    # The built client, and the dependency tree that ships.
    cp -r dist node_modules "$out"/
    # Read at run time without being imported: the configuration Bun loads, the
    # licences of what ships, and the Windows launcher the manifest names.
    cp package.json bunfig.toml tsconfig.json LICENSE THIRD_PARTY_NOTICES.md "$out"/
    install -Dm644 scripts/plugin.ps1 "$out/scripts/plugin.ps1"

    # The Rust PTY host: upstream's static musl sidecar, byte-identical
    # (dontStrip above). Its record is what server/pty/host.ts checks — sha256
    # and version only; `crate` belongs to the installer and is never compared
    # here, so null.
    install -Dm755 ${ptyHost} "$out/bin/ovis-pty-sidecar"
    printf '{"crate":null,"sha256":"%s","version":"%s"}\n' \
      ${
        lib.escapeShellArg (
          builtins.convertHash {
            hash = ptyHostHash;
            toHashFormat = "base16";
          }
        )
      } "$version" > "$out/bin/ovis-pty-sidecar.json"

    # The manifest launches through `sh scripts/with-bun.sh`, which probes PATH,
    # ~/.bun/bin, mise and Homebrew for bun. herdr runs plugin commands with its
    # own environment and from a read-only tree, and the probe finds nothing
    # there (measured: exit 127); an absolute bun works from any environment.
    cp ${manifestSrc} herdr-plugin.toml
    substituteInPlace herdr-plugin.toml \
      --replace-fail '["sh", "scripts/with-bun.sh", ' '["${lib.getExe bun}", '

    # The launcher is a SOURCE-CHECKOUT entry point: scripts/plugin-launch.ts
    # installs the release's server into `$root/.ovis/server` before running
    # anything, and a store path is read-only, so every command it carries ends
    # in `EROFS: read-only file system, mkdir '…/.ovis'` (measured: herdr's own
    # startup log, exit 1). scripts/plugin.ts needs nothing writable under the
    # root — it runs the tree in place and keeps its state under
    # HERDR_PLUGIN_STATE_DIR — and it is what 0.5.3's manifest called, before
    # upstream moved to the launcher.
    #
    # The [[build]] steps go with it: they are the checkout's own installer
    # (preflight, then `plugin-launch.ts install`) for a tree Nix already built,
    # and herdr runs them only when it installs a plugin from a source, never for
    # `plugin link` (measured: a linked probe plugin's build step never ran).
    ${lib.getExe bun} run ${./rewrite-ovis-manifest.ts} herdr-plugin.toml

    # plugin.ps1 embeds the launcher path itself, so the manifest rewrite alone
    # would leave Windows pointing at it.
    substituteInPlace "$out/scripts/plugin.ps1" \
      --replace-fail 'plugin-launch.ts' 'plugin.ts'

    if grep -q 'with-bun.sh' herdr-plugin.toml; then
      echo "ovis: herdr-plugin.toml still launches through scripts/with-bun.sh" >&2
      exit 1
    fi
    # A missed rewrite ships a plugin whose every command fails on a read-only
    # root; a missed [[build]] drop ships an installer for a tree already built.
    if grep -q 'plugin-launch' herdr-plugin.toml "$out/scripts/plugin.ps1"; then
      echo "ovis: the shipped manifest or plugin.ps1 still names scripts/plugin-launch.ts" >&2
      exit 1
    fi
    if grep -q '^\[\[build\]\]' herdr-plugin.toml; then
      echo "ovis: herdr-plugin.toml still carries [[build]] steps" >&2
      exit 1
    fi

    # The rewritten manifest must still be the plugin this pin names — a
    # substitution that quietly matched nothing would otherwise ship the
    # probing launcher or a plugin herdr refuses.
    grep -qx 'id = "devswha.ovis"' herdr-plugin.toml
    grep -qx 'version = "${version}"' herdr-plugin.toml
    grep -q '^min_herdr_version = ' herdr-plugin.toml

    cp herdr-plugin.toml "$out"/

    # Closure gate against the SHIPPED tree. The buildPhase gate proves the prod
    # dependency tree is complete; this one proves the copy is. It bundles each
    # entry point from $out, so a module the walk missed fails here and names
    # itself — the class of failure that shipped a plugin whose manifest
    # pointed at a file the store did not contain. --outdir is in $TMPDIR: the
    # bundles are proof, not output.
    ( cd "$out" && ${lib.getExe bun} build "''${entryPoints[@]}" \
      --target=bun --outdir="$TMPDIR/installed-gate" )

    # Every command the manifest runs must exist in the tree that ships: read
    # the paths out of the rewritten manifest and check each one. Bun resolves
    # imports, not manifest strings, so nothing above covers this.
    ${lib.getExe bun} -e '
      import { existsSync } from "node:fs";
      const out = process.argv[1];
      const text = await Bun.file(out + "/herdr-plugin.toml").text();
      const paths = [...text.matchAll(/"((?:scripts|server)\/[^"]+)"/g)].map((m) => m[1]);
      const missing = paths.filter((p) => !existsSync(out + "/" + p));
      if (missing.length) {
        console.error("ovis: manifest names missing files: " + missing.join(", "));
        process.exit(1);
      }
    ' "$out"

    runHook postInstall
  '';

  meta = {
    description = "Ovis — browser and phone client for herdr (built from source)";
    homepage = "https://github.com/devswha/ovis";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
