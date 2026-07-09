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
            },
            win = {
              list = {
                keys = {
                  ["Y"] = "copy_path_to_clipboard",
                },
              },
            },
          },
        },
      },
    },
  },
}
