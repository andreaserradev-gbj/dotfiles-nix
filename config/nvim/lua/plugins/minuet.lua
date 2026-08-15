-- AI completion via minuet-ai, surfaced in the blink.cmp menu (no ghost text).
--
-- Cloud-only: deepseek-v4-flash through Ollama's cloud proxy. No local model,
-- so no presets to switch between. Ollama here only proxies -- it holds no
-- weights, and `ollama list` is cloud tags exclusively.
--
-- Needs no API key: Ollama proxies under whatever account `ollama signin` set
-- up on this machine. Minuet reads the env var *named* by api_key, so "TERM"
-- is a dummy that is always set.
--
-- deepseek runs chat-mode, not FIM. Ollama's /v1/completions returns ALWAYS
-- EMPTY for it: that endpoint gives a thinking model no way to switch reasoning
-- off, so it burns the whole budget reasoning. Hence /v1/chat/completions with
-- reasoning_effort = "none", which is load-bearing -- drop it and every
-- completion comes back as "".
--
-- Measured ~0.9s per completion on the macOS sibling of this config, flat, with
-- no cold-start penalty (no local model to evict). That latency is what decides
-- whether a suggestion lands in the menu before you have typed past it.
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
      provider = "openai_compatible",
      n_completions = 1,
      -- CHARACTERS, not tokens (minuet's utils.lua uses strchars), split
      -- context_ratio 0.75 into 12000 before the cursor and 4000 after. Biggest
      -- accuracy lever there is. A cloud model does not pay latency for context
      -- the way a local one does, so this runs high.
      context_window = 16000,
      request_timeout = 5,
      throttle = 1500,
      debounce = 600,

      provider_options = {
        openai_compatible = {
          api_key = "TERM",
          name = "OllamaCloud",
          end_point = "http://localhost:11434/v1/chat/completions",
          model = "deepseek-v4-flash:cloud",
          optional = {
            -- Output budget only -- no effect on what the model sees.
            max_tokens = 256,
            top_p = 0.9,
            reasoning_effort = "none", -- see header; without it, "" every time
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
            -- Must clear minuet's own request_timeout (5s) so blink does not
            -- give up on the source first.
            timeout_ms = 6000,
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
