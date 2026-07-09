-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "gitcommit" },
  callback = function()
    vim.opt_local.spell = false
  end,
})

vim.api.nvim_create_autocmd("VimEnter", {
  desc = "Open Snacks explorer only when starting on a directory",
  once = true,
  callback = function()
    local arg = vim.fn.argv(0)
    if arg == "" then
      return
    end

    local stat = vim.uv.fs_stat(arg)
    if not stat or stat.type ~= "directory" then
      return
    end

    local dir = vim.fn.fnamemodify(arg, ":p")

    vim.schedule(function()
      -- Replace the directory buffer nvim created with an empty scratch buffer
      -- so the snacks explorer (sidebar layout) has a main window to attach to.
      local empty = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(empty)

      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if buf ~= empty and vim.api.nvim_buf_is_loaded(buf) then
          local name = vim.api.nvim_buf_get_name(buf)
          if name == arg or vim.fn.fnamemodify(name, ":p") == dir then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
          end
        end
      end

      Snacks.explorer({ cwd = dir })
    end)
  end,
})
