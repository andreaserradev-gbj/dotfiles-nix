{ pkgs, ... }:
let
  # Effort variants are what Ctrl+T ("Cycle model variants") cycles and what
  # `/review`-style subtask commands inherit. opencode auto-derives them
  # from models.dev, but its derivation function (verified in the 1.15.10
  # bundle) returns NO variants for any model whose id contains "glm" — so
  # without this block Ctrl+T shows nothing for these models and effort is
  # fixed at whatever `options` sets. Each variant's `options` is the
  # full passthrough object, so it must repeat the effort key it exists to
  # vary. ollama honors low/high/max per the model cards (glm-5.3 also
  # accepts max as its default; glm-5.3-flash publishes low/high/max).
  #
  # Placement is load-bearing: the schema defines `variants` per MODEL entry
  # (`provider.<name>.models.<id>.variants`), not on the provider, and the
  # 1.15.10 TUI builds its Ctrl+T list from exactly that path
  # (`providers.find(...).models[modelID].variants`). At provider level the
  # key loads silently but is dead config — "no variants available" on Ctrl+T.
  effortVariants = {
    low = {
      options.reasoningEffort = "low";
    };
    high = {
      options.reasoningEffort = "high";
    };
    max = {
      options.reasoningEffort = "max";
    };
  };
in
{
  # opencode ships a self-updater that offers to replace a Nix-managed binary.
  # Accepting would leave the config declaring 1.15.10 while the machine ran
  # something else — drift the drvPath gate cannot see, because it happens
  # outside the store. Same hazard btop.nix guards against with
  # `save_config_on_exit = false`: a tool that rewrites what Nix declares turns
  # the config into a lie.
  #
  # claude-code is no longer installed; this module previously contrasted its
  # DISABLE_AUTOUPDATER=1 wrapper with opencode's lack of one. opencode has no
  # such wrapper, so the off switch has to come from config. Version freshness
  # comes from `nix flake update`.
  #
  # The package itself lives in environment.systemPackages (the harness is
  # machine-level); this module owns only the per-user config.
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";

    autoupdate = false;

    # Both models are cloud stubs that the local daemon proxies to ollama.com,
    # so this is NOT on-box inference: each host needs its own `ollama signin`
    # and the 890M never sees the work. Pull a real model to change that.
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
      #
      # The camelCase `reasoningEffort` key is now VERIFIED to reach ollama as
      # snake_case `reasoning_effort` (was unverified before 1.15.10): the
      # config-side options merge into providerOptions under the provider name
      # ("ollama"), and the @ai-sdk/openai-compatible adapter maps
      # `D.reasoningEffort` to `reasoning_effort` in the request body.
      models = {
        "glm-5.3-flash:cloud" = {
          name = "GLM 5.3 Flash (cloud)";
          attachment = true;
          modalities.input = [
            "text"
            "image"
          ];
          modalities.output = [ "text" ];
          options.reasoningEffort = "high";
          # effortVariants is bound once in the `let` above; the key must be
          # spelled `variants` (see the comment in the `let` for why this has
          # to sit at model level and repeat `options` per variant).
          variants = effortVariants;
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
        # glm-5.3:cloud is a cloud stub proxied to ollama.com, same family as
        # the entry above (753B; `/api/show` on 2026-08-29 reports vision is
        # ABSENT — completion/thinking/tools only, unlike glm-5.3-flash). The
        # card says "1M" with no trimmed figure and `/api/show` reports the
        # full 1048576, so the limit is exact. Output cap is unverified —
        # 131072 follows the other ollama cloud models.
        # reasoning_effort here additionally accepts `max` (default per the
        # card); `high` is kept to match the measured-behaviour pattern noted
        # above. glm-5.3 reports no vision capability, so it deliberately
        # omits both flags.
        "glm-5.3:cloud" = {
          name = "GLM 5.3 (cloud)";
          options.reasoningEffort = "high";
          variants = effortVariants;
          limit = {
            context = 1048576;
            output = 131072;
          };
        };
        # qwen3-coder:30b-a3b-q4_K_M is the one LOCAL model here (the entries
        # above are cloud stubs), so no `ollama signin` is involved and the
        # daemon's cap is the whole story. `/api/show` on 2026-08-27 reports
        # 262144 — matching the card's 256K native window — and the daemon's
        # context is the GGUF-declared 262144, so the limit is exact, not
        # conservative. Capabilities are completion/tools only: no thinking and
        # no vision (unlike the cloud stubs, this is a non-reasoning coder), so
        # no `attachment`/`modalities`/`reasoningEffort` — `options` stays empty
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
      };
    };

    # Per-agent model split instead of a single top-level default: plan mode
    # (analysis, planning, screenshot reading) leans on the flagship glm-5.3
    # with max effort — planning is where deep thinking pays — while build mode
    # gets the cheaper glm-5.3-flash, which per Z.ai's own benchmarks is within
    # a few points of the flagship on coding (DeepSWE 63.4 vs 66.9, NL2Repo
    # 56.3 vs 58.0) at roughly one-tenth the cost. plan keeps vision access in
    # the config because glm-5.3 has none, but plan's flash-era screenshot
    # reading is gone: glm-5.3 rejects image input, so pasted screenshots in
    # plan mode become text-only. Both are primary agents, so Tab cycles
    # between them mid-session and subagents inherit whichever is active.
    # plan's effort IS pinned here via `variant = "max"` — the schema's
    # per-agent default variant, resolved when the agent's model matches and
    # the variant exists in that model's `variants` — so the footer's model
    # label shows the max suffix from session start. Ctrl+T can still cycle
    # down mid-session for a quick question; build keeps no pin and rests on
    # the per-model `options` default (high). Any agent without a `model` key
    # (e.g. qwen3-coder users via subagents) falls back to the top-level
    # `model` below.
    agent = {
      plan = {
        model = "ollama/glm-5.3:cloud";
        variant = "max";
        permission = {
          # The ONLY difference from build mode: plan cannot edit files. There
          # is deliberately no `bash` block here — earlier experiments with
          # `bash = "ask"` + a read-only allowlist (kept in git history) showed
          # why: the catch-all prompts for every unlisted command, compound
          # calls are evaluated per segment so any glue command not listed
          # prompts the whole batch, and the allowlist chases the agent's
          # real usage forever. With no `bash` key, plan inherits the exact
          # same (default) bash behaviour as build; plan is kept read-only by
          # the edit block plus its own prompt instructions, not by shell
          # gating.
          edit = "deny";
        };
      };
      build.model = "ollama/glm-5.3-flash:cloud";
    };

    model = "ollama/glm-5.3-flash:cloud";

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
