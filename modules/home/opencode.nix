{
  lib,
  osConfig,
  pkgs,
  ...
}:
lib.mkIf osConfig.local.dev.enable {
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

    # Cloud stub proxied to ollama.com, so this is NOT on-box inference: each
    # host needs its own `ollama signin` and the 890M never sees the work. It
    # is the only cloud model here now -- ollama's subscription change retired
    # glm-5.3:cloud. Pull a real model to change that.
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
        # qwen3-coder:30b-a3b-q4_K_M is a LOCAL model (the glm-5.3-flash entry
        # above is the only cloud stub), so no `ollama signin` is involved and the
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
      };
    };

    # No custom agents. opencode's built-in plan agent already denies edits;
    # both plan and build run on the top-level `model` below. Switch models
    # mid-session with Ctrl+T (model list) or Tab (plan/build).

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
