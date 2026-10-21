# registry-check.nix — the dead-code guard `deadnix` cannot provide.
#
# `deadnix --fail` (a CI gate) flags unused `let` bindings and unused lambda
# patterns. It does NOT flag an unused attrset entry. A name-keyed registry
# therefore has a dead-code hazard deadnix cannot see: a feature that is
# registered but named by nobody. This check closes that gap.
#
# Run it as:
#
#   nix eval --json --impure --expr 'import ./features/registry-check.nix'
#
# On success it prints { "ok": true, "orphaned": [], ... } and exits 0; on
# failure it throws, naming the orphaned features, and exits non-zero — so it
# is usable as a CI step as-is.
#
# WHY THIS IS NOT A REGEX OVER THE FILES
#
# The obvious implementation — grep the consumer files for "features.nixos.dev"
# — has two silent false-positive modes, and both make the guard pass exactly
# when it is needed:
#
#   1. A COMMENT that mentions the name. This repo comments heavily, so
#      "# features.nixos.dev moved to ..." would count as a consumer.
#   2. A STRING that contains the name — an error message, say.
#
# So the scan strips comments and string contents first and looks at CODE only.
# Nix has no builtin parser (`builtins.parseNixFile` does not exist), so the
# scanner below is a small hand-written one over the file's characters. It
# handles Nix's four lexical forms: line comments, double-quoted strings,
# indented strings (with `''$` / `''\` escapes), and `${...}` interpolation
# inside any string.
#
# The scanner errs towards CODE: an expression it cannot classify is treated
# as code, not as a comment. A false "consumer" is a weaker failure than a
# false "orphan", because the latter blocks a legitimate commit.

let
  registry = import ./registry.nix;

  # The files that can name a feature: the flake (the shared import list), the
  # Home Manager entrypoint, and every .nix file under every host directory —
  # a host may import a feature from any file it pulls in, not just its
  # default.nix, and a host directory may gain a subdirectory later.
  #
  # `disk-config.nix` is included on purpose. bootstrap.sh fetches it by
  # literal URL, but that does not make it un-importable: it is still a NixOS
  # module file, and a host may import from it like any other.
  nixFilesIn =
    dir:
    let
      listing = builtins.readDir dir;
      names = builtins.attrNames listing;
      isDir = n: listing.${n} == "directory";
      subdirs = map (n: dir + "/${n}") (builtins.filter isDir names);
      files = map (n: dir + "/${n}") (builtins.filter (n: !isDir n) names);
    in
    builtins.filter (f: builtins.match ".*[.]nix$" (builtins.baseNameOf f) != null) files
    ++ builtins.concatMap nixFilesIn subdirs;

  consumerFiles = [
    ../flake.nix
    ../home.nix
  ]
  ++ builtins.concatMap nixFilesIn (
    map (name: ../hosts + "/${name}") (builtins.attrNames (builtins.readDir ../hosts))
  );

  # ---- the lexer ------------------------------------------------------------

  # The tokens that change the scanner's state. The alternation order matters:
  # `''$` and `''\\` must be tried before `''`, and a backslash escape before
  # `"` so that an escaped quote does not end a string.
  #
  # The brackets are not decoration: Nix's regex engine is POSIX ERE, where a
  # backslash before a closing paren escapes it (`(''\)` is an invalid
  # expression, not a match), and where `\{` and `\}` are not escapes at all.
  # Inside a bracket expression a backslash is LITERAL, so `[\"]` is the way to
  # spell a double quote, and a bracket expression like `[\\.]` would match a
  # backslash OR a dot — the backslash escape therefore has to sit outside the
  # brackets, as `\\.`.
  #
  # `''[\\$]` would be wrong: it matches `''\` — a single backslash — but in
  # Nix the indented-string escapes are `''$` and `''\\` (TWO backslashes). A
  # lone `''\` is an escaped backslash followed by an escape, and matching it
  # as one token swallows the backslash that should escape the next character.
  delimiter = "(''\\$|''\\\\\\\\|''|\\\\.|[\"]|[#]|([$][{])|[{]|[}])";

  # `builtins.split` with a capture group returns
  #   [ segment, [ group, null ], segment, [ group, null ], … ]
  # so the pieces of a file are the even-indexed segments interleaved with the
  # odd-indexed groups.
  pieces =
    text:
    let
      raw = builtins.split delimiter text;
      n = builtins.length raw;
      count = (n + 1) / 2;
    in
    builtins.concatMap (
      i:
      let
        segment = builtins.elemAt raw (i * 2);
        group = if i * 2 + 1 < n then builtins.elemAt raw (i * 2 + 1) else [ ];
      in
      (
        if segment == "" then
          [ ]
        else
          [
            {
              kind = "text";
              value = segment;
            }
          ]
      )
      ++ (
        if group == [ ] then
          [ ]
        else
          [
            {
              kind = "delim";
              value = builtins.head group;
            }
          ]
      )
    ) (builtins.genList (i: i) count);

  # The scanner. The state is a stack of frames, innermost first:
  #
  #   code     — ordinary code (top level, or inside an interpolation)
  #   dq       — inside a "..." string
  #   ind      — inside a ''...'' string
  #   interp   — inside ${...}; `depth` counts the braces still open
  #   comment  — inside a # comment, which ends at the next newline
  #
  # The result is the file's CODE: comments and string contents removed, so
  # only attribute paths that Nix would actually evaluate remain.
  scan =
    text:
    let
      step =
        ps: stack: acc:
        if ps == [ ] then
          builtins.concatStringsSep "" acc
        else
          let
            piece = builtins.head ps;
            rest = builtins.tail ps;
            top =
              if stack == [ ] then
                {
                  kind = "code";
                  depth = 0;
                }
              else
                builtins.head stack;
            below = if stack == [ ] then [ ] else builtins.tail stack;
          in
          if piece.kind == "text" then
            if top.kind == "comment" then
              # A comment runs to the end of the line; the rest of the text
              # piece after that newline is code again.
              #
              # `builtins.split` always interleaves empty lists for its
              # capture groups — even with no group in the pattern — so the
              # segments have to be filtered back out before they can be
              # joined. The join is bound to a name first: a two-argument
              # builtin called directly inside a list literal is parsed as a
              # partial application, which is a function, not a string.
              let
                lines = builtins.filter builtins.isString (builtins.split "\n" piece.value);
                after_ = builtins.concatStringsSep "\n" (builtins.tail lines);
              in
              if builtins.length lines == 1 then
                step rest stack acc
              else
                step rest below (acc ++ [ ("\n" + after_) ])
            else if top.kind == "dq" || top.kind == "ind" then
              step rest stack acc
            else
              step rest stack (acc ++ [ piece.value ])
          else
            let
              d = piece.value;
            in
            if top.kind == "comment" then
              # Delimiters inside a comment are just text.
              step rest stack acc
            else if top.kind == "dq" then
              if d == "\"" then
                step rest below acc
              else if d == "\${" then
                step rest (
                  [
                    {
                      kind = "interp";
                      depth = 1;
                    }
                  ]
                  ++ stack
                ) acc
              else
                step rest stack acc
            else if top.kind == "ind" then
              if d == "''" then
                step rest below acc
              else if d == "''$" || d == "''\\\\" then
                step rest stack acc
              else if d == "\${" then
                step rest (
                  [
                    {
                      kind = "interp";
                      depth = 1;
                    }
                  ]
                  ++ stack
                ) acc
              else
                step rest stack acc
            else if top.kind == "interp" then
              if d == "{" then
                step rest (
                  [
                    {
                      kind = "interp";
                      depth = top.depth + 1;
                    }
                  ]
                  ++ stack
                ) (acc ++ [ "{" ])
              else if d == "}" then
                if top.depth == 1 then
                  step rest below (acc ++ [ "}" ])
                else
                  step rest (
                    [
                      {
                        kind = "interp";
                        depth = top.depth - 1;
                      }
                    ]
                    ++ stack
                  ) (acc ++ [ "}" ])
              else if d == "#" then
                step rest (
                  [
                    {
                      kind = "comment";
                      depth = 0;
                    }
                  ]
                  ++ stack
                ) acc
              else if d == "\"" then
                step rest (
                  [
                    {
                      kind = "dq";
                      depth = 0;
                    }
                  ]
                  ++ stack
                ) acc
              else if d == "''" then
                step rest (
                  [
                    {
                      kind = "ind";
                      depth = 0;
                    }
                  ]
                  ++ stack
                ) acc
              else if d == "\${" then
                step rest (
                  [
                    {
                      kind = "interp";
                      depth = 1;
                    }
                  ]
                  ++ stack
                ) acc
              else
                step rest stack acc
            else if d == "#" then
              step rest (
                [
                  {
                    kind = "comment";
                    depth = 0;
                  }
                ]
                ++ stack
              ) acc
            else if d == "\"" then
              step rest (
                [
                  {
                    kind = "dq";
                    depth = 0;
                  }
                ]
                ++ stack
              ) acc
            else if d == "''" then
              step rest (
                [
                  {
                    kind = "ind";
                    depth = 0;
                  }
                ]
                ++ stack
              ) acc
            else if d == "\${" then
              step rest (
                [
                  {
                    kind = "interp";
                    depth = 1;
                  }
                ]
                ++ stack
              ) acc
            else if d == "{" then
              step rest stack (acc ++ [ "{" ])
            else if d == "}" then
              step rest stack (acc ++ [ "}" ])
            else
              step rest stack acc;
    in
    step (pieces text) [ ] [ ];

  # ---- matching -------------------------------------------------------------

  # A registry reference in code is an attribute path ending in the feature's
  # class and name. Two spellings are in use, and one pattern covers both:
  #
  #   features.nixos.dev      — the `let` binding form
  #   ).nixos.niri            — the inline import form, i.e.
  #                             (import ../../features/registry.nix).nixos.niri
  #
  # The name must end at a non-identifier character, so `features.nixos.dev`
  # does not match the name `developer` — and it must not be preceded by a
  # path separator, so `./modules/nixos/dev.nix` never counts as a reference
  # to the `dev` feature.
  referencePattern = cls: name: ".*\\." + cls + "\\." + name + "([^A-Za-z0-9_]|$).*";

  # Each consumer file, with its text read once. `code` is a let-binding, so
  # it is computed at most once per file — and only when the cheap raw-text
  # pre-filter below says the file mentions the feature at all.
  fileData = map (f: { text = builtins.readFile f; }) consumerFiles;

  # A feature is consumed when a consumer file names it in CODE. The raw-text
  # pre-filter is sound: stripping comments and strings can only remove
  # occurrences, never add them.
  isConsumed =
    cls: name:
    let
      pattern = referencePattern cls name;
    in
    builtins.any (
      f: builtins.match pattern f.text != null && builtins.match pattern (scan f.text) != null
    ) fileData;

  # The registry flattened to a list of { class, name } pairs.
  classNames = builtins.attrNames registry;

  entries = builtins.concatLists (
    map (cls: map (name: { inherit cls name; }) (builtins.attrNames registry.${cls})) classNames
  );

  consumed = builtins.filter (e: isConsumed e.cls e.name) entries;
  orphaned = builtins.filter (e: !isConsumed e.cls e.name) entries;

  # A registry entry must be a PATH, or a list of paths. A module — or a
  # deferredModule, or a wrapper — adds a level to the import graph, which
  # reorders the list-valued contributions and moves drvPaths. That is the
  # failure this registry's shape exists to avoid (doc/dendritic-pattern.md),
  # so it is checked mechanically rather than left to review.
  isPathEntry = v: builtins.isPath v;
  isPathList = v: builtins.isList v && builtins.all isPathEntry v;

  badShape = builtins.filter (e: !(isPathEntry e.value || isPathList e.value)) (
    builtins.concatLists (
      map (
        cls:
        map (name: {
          inherit cls name;
          value = registry.${cls}.${name};
        }) (builtins.attrNames registry.${cls})
      ) classNames
    )
  );

  ok = orphaned == [ ] && badShape == [ ];

  label = e: "${e.cls}.${e.name}";
in
if ok then
  {
    ok = true;
    orphaned = [ ];
    consumed = map label consumed;
    badShape = [ ];
    entries = builtins.length entries;
    consumerFiles = map (f: builtins.toString f) consumerFiles;
  }
else
  throw ''
    features/registry-check.nix: the registry and its consumers disagree.

    orphaned (registered, but named by no consumer):
      ${
        if orphaned == [ ] then
          "  (none)"
        else
          builtins.concatStringsSep "\n" (map (e: "  - " + label e) orphaned)
      }
    not a path (a module here would add a level to the import graph):
      ${
        if badShape == [ ] then
          "  (none)"
        else
          builtins.concatStringsSep "\n" (map (e: "  - " + label e) badShape)
      }

    Every registry entry must be named by a consumer — `features.<class>.<name>`
    in a let binding, or `).<class>.<name>` in an inline import. deadnix cannot
    see an unused attrset entry, which is why this check exists.
  ''
