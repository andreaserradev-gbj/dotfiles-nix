-- mdkite.nvim: renders markdown in a real browser (headings, tables, KaTeX,
-- Mermaid) with live reload via SSE. Powers the explorer `o` preview on .md
-- files; in-buffer editing stays with render-markdown.nvim.
--
-- Pure Lua together with kitehost.nvim (its embedded HTTP/SSE server), so no
-- external binaries and modules/home/neovim.nix stays untouched. Rendering
-- libraries load from a CDN in the browser (no self-host upstream yet) — the
-- docs preview is an online workflow. The server lives inside the nvim
-- process: the page is live while nvim runs and ends with it. Takeover mode
-- (the default) retargets the same browser tab on every start() instead of
-- opening new ones. setup({}) only validates config — the server starts on
-- the first start(), so eager loading (the repo default) costs nothing.
return {
  "selimacerbas/mdkite.nvim",
  dependencies = { "selimacerbas/kitehost.nvim" },
  config = function()
    require("mdkite").setup({})
  end,
}
