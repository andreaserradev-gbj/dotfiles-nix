-- AI completion via minuet-ai, surfaced in the blink.cmp menu (no ghost text).
--
-- Local-only: qwen2.5-coder:3b through Ollama on localhost:11434. No API key --
-- minuet reads the env var *named* by api_key, so "TERM" is a dummy that is
-- always set. There is no fallback and no preset to switch to; is_available()
-- only validates config strings, never the network, so a stopped Ollama just
-- means the menu quietly loses its AI entries.
--
-- This used to default to deepseek-v4-flash:cloud through Ollama's cloud
-- proxy (ollama's subscription change retired the cloud models — see
-- modules/home/opencode.nix for the same story on the opencode side). The
-- local model is the 3b, not the macOS sibling's 7b: this box (geekom) has
-- slower memory than the M4 Pro, and a decode-rate-bound local model pays
-- for every token in RAM bandwidth.
--
-- The backend is openai_fim_compatible: Ollama's /v1/completions does real
-- fill-in-the-middle for qwen (it honours `suffix`), which is why this is not
-- the chat-completions wrapper the old cloud model required. That wrapper's
-- reasoning_effort = "none" hack goes with the thinking cloud model that
-- needed it -- qwen2.5-coder is a non-reasoning coder.
--
-- Suggestions arrive on auto-trigger only; there is no manual-invoke keymap.
--
-- NOTE: this tree is copied into the store by xdg.configFile."nvim". Flakes only
-- see git-tracked files, so `git add config/nvim` before nixos-rebuild.
return {
  {
    "milanglacier/minuet-ai.nvim",
    event = "InsertEnter",
    opts = {
      provider = "openai_fim_compatible",
      n_completions = 1,
      -- CHARACTERS, not tokens (minuet's utils.lua uses strchars), split
      -- context_ratio 0.75 into 6000 before the cursor and 2000 after. Biggest
      -- accuracy lever there is -- the macOS 7b went 15/32 -> 20/32 moving from
      -- 2000 to 8000 -- but a local model pays latency for context, so this
      -- stays at 8000 rather than the 16000 the old cloud model ran at.
      context_window = 8000,
      -- 10, not 5, because a COLD local model takes seconds to answer and that
      -- failure is silent: the request is dropped and the menu just shows
      -- nothing.
      --
      -- Ollama evicts idle models after 5 minutes otherwise, and the
      -- keep_alive request field is ignored on /v1, so the cold penalty
      -- recurs. On NixOS the keep-alive belongs in the service's
      -- environmentVariables, not launchctl (that was the macOS recipe).
      request_timeout = 10,
      throttle = 1000,
      debounce = 400,

      provider_options = {
        openai_fim_compatible = {
          api_key = "TERM",
          name = "Ollama",
          end_point = "http://localhost:11434/v1/completions",
          model = "qwen2.5-coder:3b",
          optional = {
            -- Dominant latency dial locally -- the macOS 7b on an M4 Pro
            -- measured 64 -> 1.45s, 128 -> 2.80s, 256 -> 5.54s; the 3b on
            -- this box's slower memory is in the same order of magnitude.
            max_tokens = 64,
            top_p = 0.9,
          },
        },
      },
    },
  },

  {
    "saghen/blink.cmp",
    optional = true,
    opts = {
      sources = {
        -- LazyVim declares sources.default in opts_extend, so this appends
        -- rather than replacing lsp/path/snippets/buffer.
        default = { "minuet" },
        providers = {
          minuet = {
            name = "minuet",
            module = "minuet.blink",
            async = true,
            -- Must clear minuet's own request_timeout (10s) so blink does not
            -- give up on the source first: a cold local model takes seconds.
            timeout_ms = 10000,
            -- Ranks minuet above the LSP items rather than below them.
            score_offset = 50,
          },
        },
      },
      -- Avoid firing a model request on every insert-mode keypress.
      completion = { trigger = { prefetch_on_insert = false } },
    },
  },
}