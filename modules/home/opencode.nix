{ pkgs, ... }:
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

      # Context is set from what OLLAMA reports (`/api/show`), not from what the
      # model cards claim, because the local daemon is what enforces it: it caps
      # glm-5.2 at 1000000 and minimax-m3 at 524288. models.dev lists minimax-m3
      # at 1000000+, which would overrun this path.
      #
      # `output` is not optional — opencode's schema requires it whenever
      # `limit` is present. ollama publishes no output cap, so 131072 comes from
      # models.dev, where every provider agrees on it for both models.
      #
      # `options` is a free-form passthrough to the provider SDK. ollama does
      # honour `reasoning_effort` — low vs high measured 49 vs 436 characters of
      # reasoning on the same prompt — but whether opencode translates this
      # camelCase key into that snake_case one is UNVERIFIED. Check by comparing
      # thinking length across a change of this value before trusting it.
      models = {
        "glm-5.2:cloud" = {
          name = "GLM 5.2 (cloud)";
          options.reasoningEffort = "high";
          limit = {
            context = 999424;
            output = 131072;
          };
        };
        "minimax-m3:cloud" = {
          name = "MiniMax M3 (cloud)";
          attachment = true;
          modalities.input = [
            "text"
            "image"
          ];
          modalities.output = [ "text" ];
          options.reasoningEffort = "high";
          limit = {
            context = 524288;
            output = 131072;
          };
        };
        # glm-5.3-flash:cloud is a cloud stub proxied to ollama.com, same as the
        # entries above. Card claims 1M context; the local daemon is what
        # enforces the cap, so this mirrors glm-5.2:cloud's 999424 (1M minus
        # overhead) until `/api/show` is checked on this host. Output cap is
        # unverified — 131072 follows the other ollama cloud models.
        # glm-5.3-flash and minimax-m3 are both multimodal (`ollama show` reports
        # `vision` on both; models.dev live lists minimax-m3 as text+image+video).
        # Two config keys gate image input, and they are NOT interchangeable
        # (verified against the 1.15.10 bundle): `attachment = true` reaches
        # `capabilities.attachment` (model-advertising / picker level), but the
        # send-time gate in opencode reads `capabilities.input.image`, which
        # resolves from `v.modalities.input` — NOT from `attachment`. The merge
        # for every input modality is `config.modalities.input ?? (models.dev
        # capabilities) ?? false`, and glm-5.3-flash is absent from models.dev,
        # so without the explicit array opencode replaces any attached image with
        # an "ERROR: this model does not support image input" text stub and never
        # forwards the bytes. glm-5.2 is the only text-only stub left, so it
        # deliberately omits both flags.
        "glm-5.3-flash:cloud" = {
          name = "GLM 5.3 Flash (cloud)";
          attachment = true;
          modalities.input = [
            "text"
            "image"
          ];
          modalities.output = [ "text" ];
          options.reasoningEffort = "high";
          limit = {
            context = 999424;
            output = 131072;
          };
        };
      };
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
  };
}
