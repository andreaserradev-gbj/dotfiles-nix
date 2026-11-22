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
  # scripts/plugin.ts qrcode-generator. `bun build` fails the build when the
  # list drifts, and it names the missing package and the importing file.
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

  # What herdr can launch: the manifest's commands, plus the entry points the
  # compiled binary exposes (server/entries.ts, ENTRIES). One list, read by both
  # closure gates and by the check that each file exists in the shipped tree, so
  # a name cannot be in one place and missing from another.
  entryPoints = [
    "scripts/plugin-launch.ts"
    "scripts/plugin.ts"
    "scripts/plugin-port.ts"
    "scripts/plugin-runtime.ts"
    "scripts/plugin-state.ts"
    "server/index.ts"
    "server/managed.ts"
    "server/supervisor.ts"
    "server/remote-entry.ts"
    "server/herdr-core/machine-entry.ts"
    "server/ssh-askpass.ts"
    "server/windows-launch.ts"
    "server/browser-mcp.ts"
  ];

  # The scripts the manifest and the launcher reach, by name. Not "all of
  # scripts/": upstream keeps 400+ browser-QA and fixture scripts there, 7 MiB
  # of nothing a running plugin reads. The closure gate re-bundles from $out, so
  # a file missing here fails the build instead of shipping.
  scriptsClosure = [
    "plugin-launch.ts"
    "plugin.ts"
    "plugin-port.ts"
    "plugin-runtime.ts"
    "plugin-state.ts"
    "plugin-tui.ts"
    "plugin-link.ts"
    "plugin-recover.ts"
    "plugin-confirm.ts"
    "pty-sidecar.ts"
    "server-install.ts"
    "server-manifest.ts"
    "preflight.sh"
    "preflight.ps1"
    "plugin.ps1"
    "bun-path.sh"
  ];

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

    # Vite writes node_modules/.cache and dist/, and a store input is
    # read-only, so the build runs in a writable copy.
    export HOME=$PWD/.home
    mkdir -p "$HOME"
    chmod -R u+w .
    cp -r ${devTree} node_modules
    chmod -R u+w node_modules

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
    ${lib.getExe bun} build \
      ${lib.escapeShellArgs entryPoints} \
      --target=bun --outdir="$TMPDIR/closure-gate"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"/{bin,scripts}

    # What the plugin runs: the server, the shared protocol, the scripts the
    # manifest and the launcher reach, the built client, the manifests. Tests,
    # fixtures and the browser-QA scripts beside them are megabytes of nothing a
    # running server reads.
    #
    # This list is not trusted on its own: the closure gate at the end of this
    # phase re-bundles the entry points FROM $out, so a module this list misses
    # fails the build and names itself. That is the 0.5.4 failure mode — the
    # list was frozen at the four 0.5.3 scripts while the manifest had moved on
    # to scripts/plugin-launch.ts, so the plugin linked and every command died
    # with "Module not found" while the build stayed green.
    cp -r server shared dist node_modules "$out"/
    find "$out/server" "$out/shared" -name '*.test.ts' -delete
    rm -rf "$out/server/fixtures"
    # src/lib, not all of src/: the entry points reach the relay/account code
    # under src/lib (plugin-link.ts → src/lib/account/* → src/lib/relay/*) and
    # nothing else there — src/components and src/App.tsx are the Vite build's
    # input, already bundled into dist/.
    install -d "$out/src"
    cp -r src/lib "$out/src/lib"
    find "$out/src" \( -name '*.test.ts' -o -name '*.test.tsx' \) -delete
    rm -rf "$out/src/lib/fixtures-input-rows"
    ${lib.concatMapStringsSep "\n" (
      f: ''install -Dm644 "${src}/scripts/${f}" "$out/scripts/${f}"''
    ) scriptsClosure}
    cp package.json bunfig.toml tsconfig.json LICENSE THIRD_PARTY_NOTICES.md "$out"/

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
    if grep -q 'with-bun.sh' herdr-plugin.toml; then
      echo "ovis: herdr-plugin.toml still launches through scripts/with-bun.sh" >&2
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
    # entry point from $out, so a module the installPhase list forgot, or one
    # upstream added between tags, fails here and names itself — the class of
    # failure that shipped a plugin whose manifest pointed at a file the store
    # did not contain. --outdir is in $TMPDIR: the bundles are proof, not output.
    ( cd "$out" && ${lib.getExe bun} build \
      ${lib.escapeShellArgs entryPoints} \
      --target=bun --outdir="$TMPDIR/installed-gate" )

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
