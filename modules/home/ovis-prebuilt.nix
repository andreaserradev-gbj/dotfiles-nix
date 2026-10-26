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
#
# Why two dependency FODs. `bun install` needs the network, and a sandboxed
# derivation has not got it (`DNSResolveFailed` under `sandbox = true`).
# Fixed-output derivations are the only class Nix exempts from the network
# namespace, so each tree is fetched as one:
#   dev  (441 MiB x86_64 / 434 MiB aarch64) — the whole lock; vite and
#                                             typescript-api for the build.
#   prod (2.0 MiB either arch)             — the runtime allowlist; ships.
# The production tree is NOT `bun install --production`: that resolves 302 MiB
# (mermaid, lucide-react, katex…), none of which the server or the built client
# loads. The allowlist is what the closure gate below proves sufficient.
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

  ptyHostHash =
    {
      x86_64-linux = "sha256-6gneAxc05jCiORTjfKY9Ix/QEKocQh7WjSGsMd4NYMk=";
      aarch64-linux = "sha256-cnztNui4kvPHoYR2PFLLH/c+Xbp85jJ405Qs85oh2oY=";
    }
    .${system} or (throw "ovis-prebuilt: unsupported system ${system}");

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
    ${lib.getExe bun} build \
      scripts/plugin.ts scripts/plugin-port.ts scripts/plugin-runtime.ts scripts/plugin-state.ts \
      server/index.ts server/managed.ts server/supervisor.ts \
      --target=bun --outdir="$TMPDIR/closure-gate"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"/{bin,scripts}

    # What the plugin runs: the server, the shared protocol, the four scripts
    # its manifest names, the built client, the manifests. Tests and fixtures
    # are 5.6 MiB + 2.2 MiB of nothing a running server reads.
    cp -r server shared dist node_modules "$out"/
    find "$out/server" "$out/shared" -name '*.test.ts' -delete
    rm -rf "$out/server/fixtures"
    for f in plugin.ts plugin-port.ts plugin-runtime.ts plugin-state.ts; do
      cp "scripts/$f" "$out/scripts/"
    done
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
