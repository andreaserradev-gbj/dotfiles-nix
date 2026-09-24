{
  lib,
  osConfig,
  pkgs,
  ...
}:
lib.mkIf osConfig.local.dev.enable {
  # opencode ships a self-updater that offers to replace a Nix-managed binary,
  # leaving the config a lie the drvPath gate cannot see — hence
  # `autoupdate = false`, its only off switch. Freshness comes from the unstable
  # pin in modules/nixos/dev.nix plus `nfu`. The package lives in
  # environment.systemPackages; this module owns only the per-user config.
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";

    autoupdate = false;

    # Relative instruction globs resolve upward from the session's starting
    # directory, NOT relative to this config file (that is the `{file:...}`
    # substitution's rule), so one global entry covers any repo that has the file
    # and is a no-op elsewhere. Neither path is read by opencode's built-in
    # CLAUDE.md compatibility, which covers only the project CLAUDE.md.
    instructions = [
      ".claude/rules/*.md"
      "CLAUDE.local.md"
    ];

    # Cloud stubs proxied to ollama.com — NOT on-box inference, so each host needs
    # its own `ollama signin` and the local GPU never sees the work. baseURL is
    # the literal 127.0.0.1 because ollama binds loopback only, while `localhost`
    # resolves to ::1 first on these hosts.
    provider.ollama = {
      npm = "@ai-sdk/openai-compatible";
      name = "Ollama";
      options.baseURL = "http://127.0.0.1:11434/v1";

      # Limits mirror what the DAEMON reports (`/api/show`), not what the model
      # cards claim, falling back to models.dev where ollama publishes nothing;
      # the measured numbers live in doc/local-llm.md. `output` is not optional —
      # opencode's schema requires it whenever `limit` is present.
      models = {
        "glm-5.3-flash:cloud" = {
          name = "GLM 5.3 Flash (cloud)";
          attachment = true;
          modalities.input = [
            "text"
            "image"
          ];
          modalities.output = [ "text" ];
          limit = {
            context = 1048576;
            output = 131072;
          };
        };
        # Second cloud stub: same context and capabilities as glm-5.3-flash, so
        # the two-key vision gate below applies to it identically.
        "deepseek-v4.1-flash:cloud" = {
          name = "DeepSeek V4.1 Flash (cloud)";
          attachment = true;
          modalities.input = [
            "text"
            "image"
          ];
          modalities.output = [ "text" ];
          limit = {
            context = 1048576;
            output = 131072;
          };
        };
        # Two config keys gate image input and they are NOT interchangeable:
        # `attachment` only reaches the picker-level capability, while the
        # send-time gate reads `modalities.input`. This model is absent from
        # models.dev, so without the explicit array opencode replaces any
        # attached image with an "unsupported image input" stub and never
        # forwards the bytes.
        # qwen3-coder is LOCAL (the two `:cloud` entries above are the cloud
        # stubs), so no `ollama signin` and the daemon's cap is the whole story.
        # completion/tools only — no thinking, no vision — so no
        # `attachment`/`modalities`, and `options` stays empty because the model
        # ships its own generation params.
        "qwen3-coder:30b-a3b-q4_K_M" = {
          name = "Qwen3 Coder 30B A3B (local)";
          limit = {
            context = 262144;
            # No published output cap; 65536 is the most common provider figure.
            output = 65536;
          };
        };
        # Second LOCAL model. Unlike qwen3-coder this one thinks AND sees, so it
        # declares the same `attachment` + `modalities.input` image pair as the
        # cloud stubs; ollama exposes no reasoning_effort knob, so `options`
        # stays empty.
        "qwen3.6:35b-a3b-coding-mtp-q4_K_M" = {
          name = "Qwen3.6 35B A3B Coding MTP (local)";
          attachment = true;
          modalities.input = [
            "text"
            "image"
          ];
          modalities.output = [ "text" ];
          # GGUF-declared 262144 per `/api/show`, matching the card's 256K native
          # window — exact, not conservative.
          limit = {
            context = 262144;
            # No published cap; mirrors qwen3-coder above.
            output = 65536;
          };
        };
        # Third LOCAL model, and the ONE derived tag here (the registry 404s it):
        # created by an `ollama create` of the plain tag with a one-parameter
        # Modelfile (num_ctx 131072), and that baked parameter is why this entry
        # needs no daemon config — it wins over OLLAMA_CONTEXT_LENGTH at load
        # time, while the 35b keeps the env's value. `limit.context` must agree
        # with the tag, or the daemon trims prompts opencode assembled at a
        # higher limit. A reinstall must recreate the tag by hand:
        #   printf 'FROM qwen3.8:27b-mtp-q4_K_M\nPARAMETER num_ctx 131072\n' > /tmp/m
        #   ollama create qwen3.8:27b-mtp-q4_K_M-ctx128k -f /tmp/m
        # Provenance and the measured 35b-vs-27b rows: doc/local-llm.md.
        "qwen3.8:27b-mtp-q4_K_M-ctx128k" = {
          name = "Qwen3.8 27B MTP (local, 128k ctx)";
          attachment = true;
          modalities.input = [
            "text"
            "image"
          ];
          modalities.output = [ "text" ];
          # Capabilities per `/api/show`, and the tag's baked num_ctx — the
          # daemon enforces 131072 for it, so the limit is exact.
          limit = {
            context = 131072;
            output = 65536;
          };
        };
      };
    };

    # No custom agents: opencode's built-in plan agent already denies edits, and
    # both modes run on the top-level `model` below (Ctrl+T switches model).
    # Default is the deepseek-v4.1 cloud stub, kept identical to omp's
    # `modelRoles.default` so the agent-bench comparison runs the same model on
    # both harnesses (doc/omp.md).
    model = "ollama/deepseek-v4.1-flash:cloud";

    # DRIFT WARNING: the same two servers are declared in modules/home/omp.nix,
    # so an edit must land in both (cross-linked on purpose, doc/omp.md).
    #
    # An absolute store path, not `uvx` or `nix run`, both of which fetch at run
    # time — a network dependency inside a config whose point is that flake.lock
    # already pins everything. mcp-nixos is in nixpkgs, so no extra flake input.
    mcp.nixos = {
      type = "local";
      command = [ "${pkgs.mcp-nixos}/bin/mcp-nixos" ];
      enabled = true;
    };

    # Remote HTTP MCP (Upstash's Context7); no store dependency, the URL is the
    # only contract. The Bearer key IS Nix-managed, via sops-nix: the ciphertext
    # in the repo is age-encrypted to the dev-enabled hosts only, so no plaintext
    # exists outside /run/secrets. The shell export that copies it into the
    # environment is guarded (modules/home/shell.nix), and an empty var yields
    # "Bearer ", which context7 treats as anonymous rather than as a broken
    # request.
    mcp.context7 = {
      type = "remote";
      url = "https://mcp.context7.com/mcp";
      enabled = true;
      headers.Authorization = "Bearer {env:CONTEXT7_API_KEY}";
    };
  };

  # Global agent rules, user scope: this is opencode's one global instruction file
  # (a `~/.claude/CLAUDE.md` appearing later can never shadow it), NOT the same
  # mechanism as the project-relative `instructions` globs above. The SAME asset
  # is deployed to omp's native path in modules/home/omp.nix — one file, two
  # harnesses — and the store symlink means an edit MUST go through
  # config/agents/AGENTS.md.
  xdg.configFile."opencode/AGENTS.md".source = ../../config/agents/AGENTS.md;
}
