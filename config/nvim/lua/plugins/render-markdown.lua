-- render-markdown.nvim: renders markdown *inside* the buffer (headings, tables,
-- checkboxes, callouts as Unicode). Modal: rendered in normal mode, raw source
-- in insert mode. LazyVim preset keeps styling aligned with the LazyVim theme.
--
-- Icons come from LazyVim's mini.icons, markdown parsers from treesitter.lua.
return {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = { "markdown" },
  opts = {
    preset = "lazy", -- follows LazyVim conventions
    render_modes = { "n", "c", "t" }, -- raw source visible in insert mode
    completions = { lsp = { enabled = true } }, -- marksman completion for callouts
  },
  keys = {
    { "<leader>um", "<cmd>RenderMarkdown toggle<cr>", desc = "Toggle markdown render" },
    { "<leader>ub", "<cmd>RenderMarkdown preview<cr>", desc = "Rendered copy in side window" },
  },
}
