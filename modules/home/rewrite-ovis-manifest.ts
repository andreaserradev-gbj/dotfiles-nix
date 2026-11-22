// Repoints ovis's vendored herdr manifest at the tree Nix builds, for
// ovis-prebuilt.nix's installPhase. Two upstream shapes need undoing:
//
//  - every command runs scripts/plugin-launch.ts, a source-checkout entry point
//    that installs the release's server into `$root/.ovis/server`. A store path
//    is read-only, so each of its commands ends in `EROFS: read-only file
//    system, mkdir '…/.ovis'`. scripts/plugin.ts runs the tree in place.
//  - the [[build]] steps run that same installer (preflight, then
//    `plugin-launch.ts install`). Nix already built the tree, and herdr only
//    runs build steps for a plugin it installs from a source, never for
//    `plugin link`.
//
// The vendored copy in config/ovis/ stays pristine so `nfb` can diff it against
// the tag; this rewrite happens only on the way into the store.
const [file] = process.argv.slice(2);
if (file === undefined) {
  console.error("usage: rewrite-manifest.ts <herdr-plugin.toml>");
  process.exit(2);
}

let text = await Bun.file(file).text();

// The two comment lines above the launcher build step go with it.
text = text.replace(/^# the server of this version from its release[^\n]*\n/m, "");
text = text.replace(/^# the release's Rust PTY host[^\n]*\n/m, "");

// Each build step is `[[build]]` plus its `command` and `platforms` lines.
text = text.replace(/^\[\[build\]\]\n(?:command = [^\n]*\n)?(?:platforms = [^\n]*\n)?/gm, "");

// The launcher's own name appears in the comment block too; both go.
text = text.replaceAll("scripts/plugin-launch.ts", "scripts/plugin.ts");
text = text.replace(/\n{3,}/g, "\n\n");

await Bun.write(file, text);
