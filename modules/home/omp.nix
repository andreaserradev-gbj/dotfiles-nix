{
  lib,
  osConfig,
  pkgs,
  omp,
  ...
}:
let
  # Prebuilt by default — modules/home/omp-prebuilt.nix says why. Swapping this
  # for the from-source package (the flake input's
  # `packages.${pkgs.stdenv.hostPlatform.system}.default`) changes nothing about
  # the settings below. The version of record is the tag in
  # modules/home/tool-pins.json, which `nfb` bumps together with this. The
  # prebuilt binary needs nix-ld (dev-gated, modules/nixos/dev.nix).
  ompPkg = pkgs.callPackage ./omp-prebuilt.nix {
    system = pkgs.stdenv.hostPlatform.system;
  };
in
# omp (oh-my-pi) — the second coding agent, adopted per doc/adopting-tools.md and
# documented in doc/omp.md. Same gate as the other dev-only HM modules
# (herdr.nix, opencode.nix): hplaptop evaluates this to the empty config and
# never sees the package, the settings or the assets below.
#
# FILE SHAPE: `imports` must stay UNCONDITIONAL — putting the import inside the
# gate would define home-manager.users.<user>.imports, which is not an option.
# The gate inside `config` is safe: programs.omp.enable only takes effect there.
# The package is overridden to the prebuilt derivation above; the flake input's
# from-source package remains the fallback.
{
  imports = [ omp.homeManagerModules.default ];

  config = lib.mkIf osConfig.local.dev.enable {
    programs.omp = {
      enable = true;
      package = ompPkg;

      # omp rewrites its own ~/.omp/agent/config.yml at runtime (/settings,
      # /model role persistence — flock + atomic rewrite), so the upstream module
      # does not make it a store symlink: it copies a writable regular file and
      # RE-IMPOSES these declared settings on every home-manager switch. Runtime
      # edits survive until the next switch, so anything not declared here is
      # silently lost at the next rebuild.
      settings = {
        # Default model — mirrors opencode.json's `model`: the deepseek-v4.1
        # cloud stub (user pick, 2026-09-22) served by the LOCAL daemon at
        # 127.0.0.1:11434, so the 890M never sees the work. The `:high` suffix is
        # omp's thinking-level syntax (`provider/model:level`) and is declared
        # because a runtime pick is wiped by the next switch. No models.yml: omp
        # discovers ollama's per-tag context and capabilities from /api/show.
        modelRoles.default = "ollama/deepseek-v4.1-flash:cloud:high";

        # Web search walks modelRoles.web, not a model provider: without this it
        # falls through to keyless scrapes and browser-backed engines that need a
        # Chromium daemon. The ollama.com API key itself is NOT declarable — it
        # lives in omp's auth store (~/.omp/agent/agent.db, entered once per dev
        # host via /login ollama-cloud), the same manual per-host state as the
        # daemon's own `ollama signin` (doc/secrets.md).
        modelRoles.web = "web/ollama";

        # Onboarding suppression, two keys with distinct jobs. setupVersion = 2
        # marks onboarding complete (what the wizard itself writes — omp's
        # CURRENT_SETUP_VERSION) and is needed because the activation wipes the
        # runtime completion state the previous config.yml carried.
        # startup.setupWizard = false blanks all onboarding scenes even if a
        # future release bumps that constant (selectSetupScenes returns [] when
        # it is false).
        setupVersion = 2;
        "startup.setupWizard" = false;

        # The version check, off — matching herdr's update.version_check = false
        # and opencode's autoupdate = false. It GETs the GitHub releases API on
        # every launch to announce a version we could not install anyway: `omp
        # update` refuses on a /nix/store binary ("managed by Nix"), so the flake
        # pin is the only version story here.
        "startup.checkUpdate" = false;

        # User-picked UI preferences, observed being lost on a rebuild (2026-09-21)
        # because of that re-imposition. The catalog name is dark-catppuccin, not
        # catppuccin-mocha. Extend this block rather than re-picking at runtime.
        "theme.dark" = "dark-catppuccin";
        hideThinkingBlock = true;
      };
    };

    # MCP servers — omp's counterpart of opencode.json's `mcp` block, declared in
    # omp's native Claude-style shape (its opencode-compat provider stays off: it
    # would drag in opencode-only plugins and settings keys).
    #
    # DRIFT WARNING: this file and modules/home/opencode.nix hold the same two
    # servers, so an edit must land in both (cross-linked on purpose, doc/omp.md).
    #
    # home.file, NOT xdg.configFile: omp's base directory is ~/.omp/agent/, so an
    # xdg path would be silently ignored. Store symlink: a hand-edit fails loudly.
    # context7 auth is expanded from $CONTEXT7_API_KEY at discovery time (the
    # guarded export in shell.nix); an empty var yields anonymous mode rather than
    # a broken server.
    home.file.".omp/agent/mcp.json".text = builtins.toJSON {
      "$schema" = "https://json-schema.org/draft/2020-12/schema";
      mcpServers.nixos.command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
      mcpServers.context7 = {
        type = "http";
        url = "https://mcp.context7.com/mcp";
        headers.Authorization = "Bearer \${CONTEXT7_API_KEY}";
      };
    };

    # Global agent rules, user scope — the same store asset as opencode's copy
    # (config/agents/AGENTS.md). Discovery keeps only ONE user-scope context file
    # and foreign roots (`~/.config/opencode`, `~/.agents/AGENTS.md`) are opt-in
    # through `enabledProviders`, so the native path is what loads
    # deterministically. Deliberately not RULES.md: the sticky variant is re-sent
    # on every request, and these belong in the once-per-session opening context.
    home.file.".omp/agent/AGENTS.md".source = ../../config/agents/AGENTS.md;

    # Shell completions, generated from live command metadata and cached in
    # ~/.cache: the generator boots the full agent core, so regenerating on every
    # zsh start would be a measurable tax. The cache is refreshed once the binary
    # is newer than it — i.e. after a tag bump. initContent, not the deprecated
    # initExtra.
    programs.zsh.initContent = ''
      # cached; refreshed when the omp binary is newer (modules/home/omp.nix)
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
