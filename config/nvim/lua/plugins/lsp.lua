return {
  -- LSP servers + formatters come from Nix (see modules/neovim.nix), not Mason.
  -- Mason's prebuilt binaries assume an FHS layout and don't run on NixOS;
  -- disabling it makes LazyVim set the servers up directly from $PATH.
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        bashls = {},
        cssls = {},
        html = {},
        jsonls = {},
        lua_ls = {
          settings = {
            Lua = {
              completion = { callSnippet = "Replace" },
              diagnostics = { globals = { "vim" } },
              workspace = { checkThirdParty = false },
            },
          },
        },
        marksman = {},
        yamlls = {},
      },
    },
  },
}
