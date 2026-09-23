{
  lib,
  osConfig,
  pkgs,
  omp,
  ...
}:
let
  # Prebuilt-by-default: upstream's release binary (see omp-prebuilt.nix for
  # why — the from-source build costs ~31 min on a fast CI runner, >1h
  # locally, and recompiles on every nfu that moves nixpkgs-unstable). The
  # from-source fallback is one flag away: swap this for
  # `omp.packages.${pkgs.stdenv.hostPlatform.system}.default` (or build the
  # flake input's package) — settings below are identical either way, since
  # both binaries are v18.2.10 and read the same config.yml. The prebuilt
  # needs nix-ld (dev-gated, modules/nixos/dev.nix) for its /lib64 loader.
  # KEEP IN STEP with modules/home/tool-pins.json on a tag bump (`nfb`): this
  # is the version the settings were written against.
  ompPkg = pkgs.callPackage ./omp-prebuilt.nix {
    system = pkgs.stdenv.hostPlatform.system;
  };
in
# omp (oh-my-pi) — the second coding agent, adopted per doc/adopting-tools.md
# and documented in doc/omp.md. Gate matches the other dev-only HM modules
# (herdr.nix, opencode.nix): hplaptop (local.dev.enable = false) evaluates
# this to the empty config and never sees the package, the settings, or the
# two home.file assets below.
#
# The declarative settings come from omp's own HM module
# (homeManagerModules.default, threaded as the `omp` flake input via
# extraSpecialArgs); the PACKAGE is overridden to the prebuilt derivation
# above — programs.omp.package defaults to the flake's
# packages.<system>.default (the from-source build), which remains the
# fallback and the pin of record for the version.
#
# FILE SHAPE NOTE: this file has TWO top-level attributes — `imports` (the
# upstream HM module) and the `lib.mkIf` config body — because a module that
# WRAPS its imports in mkIf breaks: `imports` must be unconditional here
# (importing an upstream module that itself contains `config = mkIf … {}` is
# safe; putting the import INSIDE the gate's content is a different, broken
# thing — it would define home-manager.users.<user>.imports, which is not an
# option). Gate placement is safe: programs.omp.enable only takes effect
# inside the gated attrset below.
{
  imports = [ omp.homeManagerModules.default ];

  config = lib.mkIf osConfig.local.dev.enable {
    programs.omp = {
      enable = true;
      package = ompPkg;

      # omp rewrites its own ~/.omp/agent/config.yml at runtime (/settings,
      # onboarding, /model role persistence — flock + atomic rewrite). The
      # upstream module therefore does NOT make it a store symlink: it copies a
      # writable regular file (mode 600) in a home.activation step and
      # RE-IMPOSES these declared settings on every home-manager switch.
      # Runtime edits survive until the next switch — the inverse of
      # opencode's autoupdate = false problem. omp DOES ship an updater
      # (`omp update` + the startup version check, cli/update-cli.ts), but it
      # refuses to touch a Nix-managed binary: resolveUpdateMethod returns
      # "nix" for any path under /nix/store and the command exits with
      # "This installation is managed by Nix and cannot update itself." So
      # Nix ownership is safe by upstream guard, not by the updater's absence
      # (doc/omp.md used to claim the latter — corrected 2026-09-22 while
      # bumping to v18.2.8). The phone-home half IS ours to switch off:
      # startup.checkUpdate defaults to true and fetches the GitHub releases
      # API on every launch, and it can only ever report a version we cannot
      # install. Disabled below, exactly like herdr's update.version_check =
      # false (config/herdr/config.toml) and opencode's autoupdate = false —
      # all three tool-version stories are the flake pin.
      settings = {
        # Default model — mirrors opencode.json's `model`: the deepseek-v4.1
        # cloud stub (user pick, 2026-09-22), reached through the LOCAL daemon
        # at 127.0.0.1:11434, so the 890M never sees the work. ollama's
        # subscription change retired glm-5.3:cloud, which is what a
        # pre-dates-that config would name — same story as opencode.nix
        # lines 41-48.
        #
        # The `:high` suffix is omp's model-string syntax for the thinking
        # level (`provider/model:level`, model-selector.ts splitThinkingSuffix)
        # and is what the runtime pick in config.yml carried — declared here so
        # the next switch re-imposes it instead of silently dropping to the
        # model's default tier. opencode's `model` has no such suffix (different
        # config schema), so the two strings agree on the model and differ only
        # on the tier by construction: switching the model is one edit in each
        # file, and agent-bench compares them on the same model by design.
        #
        # No models.yml: omp discovers ollama implicitly (native /api/tags +
        # /api/show against OLLAMA_BASE_URL), so per-tag context windows and
        # vision/thinking capabilities come from the daemon itself — including
        # the derived ctx128k tag — instead of being hand-copied into config
        # where they would go stale (the exact maintenance burden opencode.nix
        # documents around its hand-maintained `limit` blocks).
        modelRoles.default = "ollama/deepseek-v4.1-flash:cloud:high";

        # Web-search routing: omp's web_search tool walks modelRoles.web, NOT
        # any LLM provider — without this it falls through to the keyless
        # chain (duckduckgo/startpage HTTP scrapes, then browser-backed
        # google/ecosia/mojeek that need a Chromium daemon, absent here).
        # "web/ollama" is omp's native provider for
        # ollama.com/api/web_search — the same backend opencode reaches
        # transparently through the signed-in daemon's cloud models.
        #
        # The credential is NOT declarable: the ollama.com API key lives in
        # omp's auth store (~/.omp/agent/agent.db, entered once per dev host
        # via the first-run wizard or /login ollama-cloud) — manual per-host
        # state mirroring the daemon's own `ollama signin` (opencode.nix).
        # agent.db is outside Nix's reach and survives rebuilds; this routing
        # line does not (see setupVersion below), which is why it is declared.
        modelRoles.web = "web/ollama";

        # Onboarding suppression, two keys with distinct jobs:
        # - setupVersion = 2 marks onboarding complete (what the wizard itself
        #   writes; omp's compiled-in CURRENT_SETUP_VERSION). Without it, every
        #   fresh switch would replay the wizard because the HM activation
        #   wipes whatever runtime completion state the previous config.yml
        #   carried.
        # - startup.setupWizard = false blanks all onboarding scenes even if a
        #   future omp release bumps CURRENT_SETUP_VERSION (traced in omp's
        #   source: selectSetupScenes returns [] when it is false) — no
        #   surprise wizard after a tag bump, mirroring opencode's
        #   autoupdate = false posture.
        setupVersion = 2;
        "startup.setupWizard" = false;

        # Third startup knob, unrelated to onboarding: the version check.
        # Default is true, and it GETs the GitHub releases API on every launch
        # (main.ts checkForNewVersion → getLatestRelease, 5 s timeout) to print
        # "a newer version exists" — a notice that can never lead to an install
        # here, because `omp update` refuses on a /nix/store binary (the
        # updater note above). Off, matching the same decision on the other two
        # tools — herdr's update.version_check = false and opencode's
        # autoupdate = false: the flake pin is the only version story, and no
        # launch pays a network round trip to restate it.
        "startup.checkUpdate" = false;

        # User-picked UI preferences. The writable-copy mechanism means
        # ANYTHING set at runtime (/settings, the theme scene) is wiped by the
        # next home-manager switch unless it is declared here — observed live
        # 2026-09-21 (the first nrs lost the trial-time theme pick and the
        # hide-thinking toggle, which omp had rewritten into config.yml).
        # These two are the user's confirmed choices (theme name verified via
        # `omp config set` — omp's catalog calls it dark-catppuccin, not
        # catppuccin-mocha); extend this block, never re-pick at runtime, when
        # another preference matters.
        "theme.dark" = "dark-catppuccin";
        hideThinkingBlock = true;
      };
    };

    # MCP servers — the omp counterpart of opencode.json's `mcp` block. omp
    # does not read opencode's config here (its opencode-compat provider is
    # deliberately left off: enabling it would also drag in the opencode-only
    # herdr plugin and feed opencode-only settings keys into omp's merge), so
    # the same two servers are declared in omp's native Claude-style shape.
    #
    # DRIFT WARNING: this file and modules/home/opencode.nix now hold the MCP
    # config in TWO places — an edit to either server must land in both.
    # Cross-linked on purpose (choice recorded in doc/omp.md): the alternative
    # (enabling omp's opencode provider) couples more than it saves.
    #
    # home.file, NOT xdg.configFile: omp's base directory is ~/.omp/agent/
    # (PI_CODING_AGENT_DIR semantics), not ~/.config/omp/ — an xdg path would
    # be silently ignored. Store symlink: a hand-edit fails loudly instead of
    # drifting, same as herdr's config.toml.
    #
    # context7 auth: "${CONTEXT7_API_KEY}" in omp's mcp.json is expanded from
    # the environment at MCP discovery time — the same {env:...}-at-connect
    # semantics opencode.json relies on, fed by the guarded export in
    # shell.nix from /run/secrets (sops-nix, dev hosts only). An empty var
    # yields "Bearer " and context7's anonymous mode, so hosts without the
    # secret degrade instead of breaking.
    home.file.".omp/agent/mcp.json".text = builtins.toJSON {
      "$schema" = "https://json-schema.org/draft/2020-12/schema";
      mcpServers.nixos.command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
      mcpServers.context7 = {
        type = "http";
        url = "https://mcp.context7.com/mcp";
        headers.Authorization = "Bearer \${CONTEXT7_API_KEY}";
      };
    };

    # Shell completions: omp generates them from live command metadata (never
    # drifts from the installed version). Cached in ~/.cache — the generator
    # boots the full agent core, so regenerating on every zsh start would be
    # a measurable startup tax. Regenerated automatically when the cached
    # file is older than the omp binary (i.e. after a tag bump).
    # initContent (not the deprecated initExtra): HM 26.05 warns on initExtra
    # and this content must not race the alias emission order anyway.
    programs.zsh.initContent = ''
      # omp completions (cached; regenerated when the omp binary is newer than
      # the cache — see modules/home/omp.nix and doc/omp.md)
      if command -v omp >/dev/null 2>&1; then
        _omp_comp_cache="''${XDG_CACHE_HOME:-$HOME/.cache}/omp/zsh-completions.zsh"
        _omp_bin="$(command -v omp)"
        if [[ ! -s "$_omp_comp_cache" || "$_omp_bin" -nt "$_omp_comp_cache" ]]; then
          mkdir -p "''${_omp_comp_cache:h}"
          omp completions zsh > "$_omp_comp_cache" 2>/dev/null
        fi
        [[ -s "$_omp_comp_cache" ]] && source "$_omp_comp_cache"
        unset _omp_comp_cache _omp_bin
      fi
    '';
  };
}
