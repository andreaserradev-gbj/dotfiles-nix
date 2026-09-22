{
  lib,
  osConfig,
  pkgs,
  ...
}:
lib.mkIf osConfig.local.dev.enable {
  # opencode ships a self-updater that offers to replace a Nix-managed binary.
  # Accepting would leave the config declaring 1.18.31 while the machine ran
  # something else — drift the drvPath gate cannot see, because it happens
  # outside the store. Same hazard btop.nix guards against with
  # `save_config_on_exit = false`: a tool that rewrites what Nix declares turns
  # the config into a lie.
  #
  # claude-code is no longer installed; this module previously contrasted its
  # DISABLE_AUTOUPDATER=1 wrapper with opencode's lack of one. opencode has no
  # such wrapper, so the off switch has to come from config — re-verified
  # against the 1.18.31 source (cli/upgrade.ts bails on `autoupdate === false`
  # before any fetch). Version freshness comes from the nixpkgs-unstable pin
  # (local.dev.opencodePackage in flake.nix's hostArgs, set by the two dev
  # hosts) plus `nfu`.
  #
  # The package itself lives in environment.systemPackages (the harness is
  # machine-level); this module owns only the per-user config.
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";

    autoupdate = false;

    # Relative instruction globs resolve upward from the project directory the
    # session starts in (re-verified against the 1.18.31 source,
    # session/instruction.ts: relative entries go through
    # globUp(instruction, ctx.directory, ctx.worktree), NOT relative to this
    # config file — that is the {file:...} substitution's rule, which resolves
    # against dir(config) in config/variable.ts). So one global entry applies
    # to any repo that has the file and is a no-op in repos that do not:
    # .claude/rules/*.md picks up per-topic scoped rules,
    # CLAUDE.local.md the per-repo personal notes. Neither is read by opencode's
    # built-in discovery — CLAUDE.md compatibility covers only the single
    # project CLAUDE.md, not Claude's rules directory or .local files.
    instructions = [
      ".claude/rules/*.md"
      "CLAUDE.local.md"
    ];

    # Cloud stubs proxied to ollama.com, so this is NOT on-box inference: each
    # host needs its own `ollama signin` and the 890M never sees the work.
    # glm-5.3:cloud was retired by ollama's subscription change; the two stubs
    # below are the current cloud lineup. Pull a real model to change that.
    #
    # baseURL is the literal address rather than `localhost` because ollama
    # binds 127.0.0.1 only, while localhost resolves to ::1 first on these
    # hosts — this does not rely on the client retrying over IPv4.
    provider.ollama = {
      npm = "@ai-sdk/openai-compatible";
      name = "Ollama";
      options.baseURL = "http://127.0.0.1:11434/v1";

      # Context is set from what OLLAMA reports, not from what the model cards
      # claim, because the local daemon is what enforces it. `/api/show` on
      # 2026-08-29: glm-5.3-flash and glm-5.3 both report 1048576, matching
      # their cards' "1M" with no published trimmed figure.
      #
      # `output` is not optional — opencode's schema requires it whenever
      # `limit` is present. ollama publishes no output cap, so 131072 comes from
      # models.dev, where every provider agrees on it for the cloud stubs.
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
        # Second cloud stub. `/api/show` on 2026-09-21 reports a 763B FP8
        # model with the same 1048576 context as glm-5.3-flash and capabilities
        # completion/thinking/tools/vision — so the same two-key vision gate
        # above applies. ollama publishes no output cap for it either; 131072
        # mirrors the glm-5.3-flash figure.
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
        # Two config keys gate image input, and they are NOT interchangeable
        # (verified against the 1.15.10 bundle): `attachment = true` reaches
        # `capabilities.attachment` (model-advertising / picker level), but the
        # send-time gate in opencode reads `capabilities.input.image`, which
        # resolves from `v.modalities.input` — NOT from `attachment`. The merge
        # for every input modality is `config.modalities.input ?? (models.dev
        # capabilities) ?? false`, and glm-5.3-flash is absent from models.dev,
        # so without the explicit array opencode replaces any attached image with
        # an "ERROR: this model does not support image input" text stub and never
        # forwards the bytes.
        # qwen3-coder:30b-a3b-q4_K_M is a LOCAL model (the two `:cloud` entries
        # above are the cloud stubs), so no `ollama signin` is involved and the
        # daemon's cap is the whole story. `/api/show` on 2026-08-27 reports
        # 262144 — matching the card's 256K native window — and the daemon's
        # context is the GGUF-declared 262144, so the limit is exact, not
        # conservative. Capabilities are completion/tools only: no thinking and
        # no vision (unlike the cloud stub, this is a non-reasoning coder), so
        # no `attachment`/`modalities` — `options` stays empty
        # since the model ships its own generation params (temp 0.7, top_p 0.8).
        "qwen3-coder:30b-a3b-q4_K_M" = {
          name = "Qwen3 Coder 30B A3B (local)";
          limit = {
            context = 262144;
            # models.dev output figures for this model disagree across
            # providers (32768-262000); Qwen's own docs give none. 65536 is the
            # most common value among providers listing 262144 context.
            output = 65536;
          };
        };
        # Second LOCAL model: qwen3.6:35b-a3b-coding-mtp-q4_K_M (35.5B MoE,
        # ~22 GB on disk; MTP = multi-token prediction for faster decode).
        # Unlike qwen3-coder this one thinks AND sees: `/api/show` on
        # 2026-09-02 reports capabilities completion/vision/tools/thinking, so
        # it declares `attachment` + `modalities.input` image — same two-key
        # vision gate as glm-5.3-flash above (opencode reads the send-time
        # gate from `modalities.input`, not `attachment`, and this model is
        # absent from models.dev). It is a reasoning model, but ollama
        # publishes no reasoning_effort knobs for it, so `options` stays empty.
        "qwen3.6:35b-a3b-coding-mtp-q4_K_M" = {
          name = "Qwen3.6 35B A3B Coding MTP (local)";
          attachment = true;
          modalities.input = [
            "text"
            "image"
          ];
          modalities.output = [ "text" ];
          # `/api/show` on 2026-09-02 reports the GGUF-declared 262144,
          # matching the card's 256K native window, so the limit is exact.
          limit = {
            context = 262144;
            # No published output cap; 65536 mirrors qwen3-coder above, the
            # only other local model with the same context figure.
            output = 65536;
          };
        };
        # Third LOCAL model: qwen3.8:27b-mtp-q4_K_M-ctx128k (27.3B, same qwen35
        # hybrid arch as the 35b above — 16 of 66 layers full attention, 4 KV
        # heads — but ~27B params ACTIVE per token, not ~3B like the MoE, so
        # decode is compute/bandwidth-bound, not placement-bound). The tag is
        # LOCAL AND DERIVED, not an upstream registry tag (registry 404s it):
        # created 2026-09-17 12:19 by an opencode session via `ollama create`
        # with a one-PARAMETER Modelfile (num_ctx 131072). That baked parameter
        # is why this entry needs no daemon config: it wins over
        # OLLAMA_CONTEXT_LENGTH=262144 at load time, while the 35b (no baked
        # num_ctx) keeps the env's 262144. At the GGUF-native 262144 the plain
        # tag does NOT fit: KV is 64 KB/token here (vs 22 on the 35b — 16
        # full-attn layers x 4 KV heads vs 11 x 2), 16 GiB at 262144, and the
        # 2026-09-17 14:21 load ran 45/66 layers with 5 GiB of KV on CPU;
        # the 14:20 load of THIS tag ran 66/66 at n_ctx 131072. `limit.context`
        # must agree with the tag (131072) — a higher client limit would have
        # opencode assemble prompts the daemon trims, the 32768-vs-262144
        # disagreement bug of 2026-09-11 in miniature. Measured same-prompt A/B
        # (seed 42, 100% GPU both): decode 33 vs 8 t/s shallow, 32 vs 10 at
        # ~12k depth; prefill 364/348 vs 97/91 — the 35b is ~4x faster at
        # everything; this tag trades speed for a bigger dense model.
        #
        # The tag is imperative daemon state (/var/lib/ollama): a reinstall
        # must recreate it by hand —
        #   printf 'FROM qwen3.8:27b-mtp-q4_K_M\nPARAMETER num_ctx 131072\n' > /tmp/m
        #   ollama create qwen3.8:27b-mtp-q4_K_M-ctx128k -f /tmp/m
        # (after the plain-tag pull); full provenance and the 27b rows live in
        # doc/local-llm.md.
        "qwen3.8:27b-mtp-q4_K_M-ctx128k" = {
          name = "Qwen3.8 27B MTP (local, 128k ctx)";
          attachment = true;
          modalities.input = [
            "text"
            "image"
          ];
          modalities.output = [ "text" ];
          # `/api/show` on 2026-09-17 reports capabilities
          # completion/vision/tools/thinking and the tag's baked num_ctx 131072;
          # the daemon enforces 131072 for this tag (14:20 load, n_ctx logged),
          # so the limit is exact, not conservative. Output cap mirrors the
          # two local models above.
          limit = {
            context = 131072;
            output = 65536;
          };
        };
      };
    };

    # No custom agents. opencode's built-in plan agent already denies edits;
    # both plan and build run on the top-level `model` below. Switch models
    # mid-session with Ctrl+T (model list) or Tab (plan/build).
    #
    # Default is the deepseek-v4.1 cloud stub (user pick, 2026-09-22) — kept
    # identical to omp's `modelRoles.default` (modules/home/omp.nix), which is
    # the point: one model, chosen on both harnesses, so the agent-bench
    # comparison in doc/omp.md runs the same model on each side.
    model = "ollama/deepseek-v4.1-flash:cloud";

    # An absolute store path, not the README's `uvx` or `nix run`: both fetch at
    # run time, which would put a network dependency inside a config whose whole
    # point is that flake.lock already pins it. mcp-nixos is in nixpkgs 26.05,
    # so this needs no new flake input.
    mcp.nixos = {
      type = "local";
      command = [ "${pkgs.mcp-nixos}/bin/mcp-nixos" ];
      enabled = true;
    };

    # Remote HTTP MCP for library/API documentation search (Upstash's Context7),
    # so no store dependency and no binary; the URL is the only contract. The
    # Bearer key IS managed by Nix now — via sops-nix, which is why this is
    # safe where the old plan (plaintext credential in repo or store) was not:
    # the ciphertext in the repo/store is age-encrypted to Andrea's personal
    # key and the host SSH keys of the dev-enabled machines only (hplaptop is
    # not a recipient and declares no secrets). No plaintext exists outside
    # /run/secrets — a tmpfs ramfs, mode 0400, wiped at reboot — and the shell
    # export that copies it into the environment is guarded (modules/home/
    # shell.nix) so hosts without the secret fall back to anonymous mode:
    # {env:V} in opencode.json resolves at MCP connect time, client-side; an
    # empty var yields "Bearer " (which context7 treats as anonymous) rather
    # than a broken request.
    mcp.context7 = {
      type = "remote";
      url = "https://mcp.context7.com/mcp";
      enabled = true;
      headers.Authorization = "Bearer {env:CONTEXT7_API_KEY}";
    };
  };
}
