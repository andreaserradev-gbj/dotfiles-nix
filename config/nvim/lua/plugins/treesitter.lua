return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = { "nix" },
      indent = {
        enable = true,
        disable = { "typescript", "tsx" },
      },
    },
  },
}
