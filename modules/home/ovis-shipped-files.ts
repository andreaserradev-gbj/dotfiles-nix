// Lists the files ovis's plugin tree ships, for ovis-prebuilt.nix's
// installPhase: every file the entry points load, found the way Bun loads it.
//
// Two kinds of edge. An import — static, or a dynamic import whose specifier is
// a literal — resolved by Bun's own resolver, so `import type` is erased and
// never reaches a file, and a tsconfig `paths` alias resolves to what it names.
// And a path written as a string literal that is no import: server/file-pool.ts
// starts its worker with `new URL("./file-worker.ts", import.meta.url)`, which
// no import reaches. A literal is resolved only beside the file naming it,
// never from the tree's root: from the root they name data the server serves
// (public/favicon.ico) and the sidecar installer (scripts/pty-sidecar.ts),
// which must not ship — it would download into a read-only root.
//
// Literals are read from the transpiled source, where comments and type-only
// imports are gone: a path in either is a mention, not a load.
//
// The bundler's source map was the alternative, and it fails both ways: it
// carries no text or file import (server/approvals/cmd.ts loads two files from
// integrations/ as text), and no module whose exports it tree-shook away,
// though the runtime still loads the file.
//
// Packages are not this script's business — the closure gate proves the prod
// tree resolves them — but a local import that resolves to nothing is: that
// tree is broken, and so is a file Bun cannot parse.
//
// usage: ovis-shipped-files.ts ROOT ENTRY…
// Prints one path, relative to ROOT, per line.
import { existsSync, readFileSync, realpathSync, statSync } from "node:fs";
import { dirname, extname, relative, resolve, sep } from "node:path";

const [root, ...entries] = process.argv.slice(2);
if (root === undefined || entries.length === 0) {
  console.error("usage: ovis-shipped-files.ts ROOT ENTRY…");
  process.exit(2);
}
const rootPath = realpathSync(root);

// Inside the tree, and a file. A resolved import that lands in node_modules is
// a package: which of those ship is the allowlist's call, not this walk's.
const inTree = (file: string): boolean => {
  const rel = relative(rootPath, file);
  return (
    rel !== "" &&
    rel !== ".." &&
    !rel.startsWith(`..${sep}`) &&
    !rel.startsWith(`node_modules${sep}`) &&
    statSync(file).isFile()
  );
};

// Anything else — json, wasm — is loaded but has nothing to scan.
const loaderOf = (file: string): "js" | "jsx" | "ts" | "tsx" | null => {
  switch (extname(file)) {
    case ".ts":
    case ".mts":
    case ".cts":
      return "ts";
    case ".tsx":
      return "tsx";
    case ".jsx":
      return "jsx";
    case ".js":
    case ".mjs":
    case ".cjs":
      return "js";
    default:
      return null;
  }
};

interface Transpiled {
  // Every runtime import's specifier, as written.
  specifiers: string[];
  // The same source transpiled: every string literal that is not an import is
  // still in it.
  javascript: string;
}

// Null when Bun cannot parse the file.
const transpile = (loader: "js" | "jsx" | "ts" | "tsx", source: string): Transpiled | null => {
  try {
    const transpiler = new Bun.Transpiler({ loader });
    const specifiers = transpiler.scan(source).imports.map((specifier) => specifier.path);
    return { specifiers, javascript: transpiler.transformSync(source) };
  } catch {
    return null;
  }
};

// A quoted path with an extension: relative, or bare beside the file naming it.
const LITERAL = /(["'`])((?:\.\.?\/)?[\w@./-]+\.[A-Za-z0-9]{1,8})\1/g;

const problems: string[] = [];
const shipped = new Set<string>();
const queue: string[] = [];

const enqueue = (target: string): void => {
  if (!existsSync(target)) return;
  const real = realpathSync(target);
  if (inTree(real)) queue.push(real);
};

for (const entry of entries) {
  if (!existsSync(resolve(rootPath, entry))) {
    console.error(`ovis: entry point missing: ${entry}`);
    process.exit(1);
  }
  enqueue(resolve(rootPath, entry));
}

while (queue.length > 0) {
  const file = queue.pop()!;
  if (shipped.has(file)) continue;
  shipped.add(file);

  const loader = loaderOf(file);
  if (loader === null) continue;
  const transpiled = transpile(loader, readFileSync(file, "utf8"));
  if (transpiled === null) {
    problems.push(`${relative(rootPath, file)}: Bun cannot parse it`);
    continue;
  }

  const dir = dirname(file);
  for (const specifier of transpiled.specifiers) {
    if (specifier.startsWith("node:") || specifier.startsWith("bun:")) continue;
    let resolved: string;
    try {
      resolved = Bun.resolveSync(specifier, dir);
    } catch {
      if (specifier.startsWith(".") || specifier.startsWith("/")) {
        problems.push(`${relative(rootPath, file)}: imports ${specifier}, which resolves to nothing`);
      }
      continue;
    }
    enqueue(resolved);
  }
  const imports = new Set(transpiled.specifiers);
  for (const match of transpiled.javascript.matchAll(LITERAL)) {
    const literal = match[2]!;
    if (!imports.has(literal)) enqueue(resolve(dir, literal));
  }
}

if (problems.length > 0) {
  for (const problem of problems) console.error(`ovis: ${problem}`);
  process.exit(1);
}
for (const file of [...shipped].sort()) console.log(relative(rootPath, file));
