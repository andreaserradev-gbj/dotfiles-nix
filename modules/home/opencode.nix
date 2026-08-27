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
        # glm-5.3-flash is the only multimodal model here — `attachment = true`
        # tells opencode to pass image inputs through. The other two are text-only
        # cloud stubs, so they deliberately omit this flag.
        "glm-5.3-flash:cloud" = {
          name = "GLM 5.3 Flash (cloud)";
          attachment = true;
          options.reasoningEffort = "high";
          limit = {
            context = 999424;
            output = 131072;
          };
        };
      };
    };

    model = "ollama/glm-5.2:cloud";

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
