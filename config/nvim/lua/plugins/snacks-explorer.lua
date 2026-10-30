return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            actions = {
              copy_path_to_clipboard = function(picker)
                local item = picker:current()
                local path = item and (item.file or item._path)
                if not path or path == "" then
                  return
                end
                vim.fn.setreg("+", path)
                vim.notify("Copied path: " .. path)
              end,
              -- `o` on a .md file opens ONLY the browser preview (mdkite via
              -- xdg-open); in-buffer editing stays with render-markdown.nvim.
              -- mdkite previews the *current* buffer, so the file is opened
              -- first (confirm) and then hidden alive — wiping it would kill
              -- the buffer-local refresh autocmds upstream. Headless hosts
              -- (no DISPLAY/WAYLAND_DISPLAY) fall back to the raw buffer.
              open_markdown_preview = function(picker)
                local item = picker:current()
                local path = item and (item.file or item._path)
                if not path or not path:match("%.md$") then
                  return picker:action("confirm")
                end
                if not vim.env.DISPLAY and not vim.env.WAYLAND_DISPLAY then
                  vim.notify("No display — opening raw buffer (no browser preview)")
                  return picker:action("confirm")
                end
                picker:action("confirm")
                vim.schedule(require("mdkite").start)
                vim.schedule(function()
                  local alt = vim.fn.bufnr("#")
                  if alt ~= -1 and alt ~= vim.api.nvim_get_current_buf() then
                    vim.cmd("buffer #")
                  else
                    vim.cmd("enew")
                  end
                end)
              end,
            },
            win = {
              list = {
                keys = {
                  ["Y"] = "copy_path_to_clipboard",
                  ["o"] = "open_markdown_preview",
                },
              },
            },
          },
        },
      },
    },
  },
}
