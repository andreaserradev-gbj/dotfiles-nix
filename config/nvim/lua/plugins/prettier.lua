return {
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.astro = { "prettier_astro" }

      opts.formatters = opts.formatters or {}
      local prettier_config_files = {
        ".prettierrc",
        ".prettierrc.json",
        ".prettierrc.js",
        ".prettierrc.cjs",
        ".prettierrc.mjs",
        ".prettierrc.yaml",
        ".prettierrc.yml",
        ".prettierrc.toml",
        "prettier.config.js",
        "prettier.config.cjs",
        "prettier.config.mjs",
      }
      opts.formatters.prettier = vim.tbl_deep_extend("force", opts.formatters.prettier or {}, {
        prepend_args = function(_, ctx)
          if vim.fs.root(ctx.filename, prettier_config_files) then
            return {}
          end
          return {
            "--tab-width",
            "4",
            "--print-width",
            "140",
            "--use-tabs",
            "false",
            "--single-quote",
            "true",
            "--trailing-comma",
            "es5",
          }
        end,
      })

      opts.formatters.prettier_astro = {
        inherit = false,
        command = function(_, ctx)
          local root = vim.fs.root(ctx.filename, { "package.json", ".prettierrc", ".prettierrc.json" })
          if root then
            return root .. "/node_modules/.bin/prettier"
          end
          return "prettier"
        end,
        cwd = require("conform.util").root_file({ "package.json", ".prettierrc", ".prettierrc.json" }),
        args = function(_, ctx)
          local args = { "--parser", "astro" }
          if not vim.fs.root(ctx.filename, prettier_config_files) then
            vim.list_extend(args, {
              "--tab-width",
              "4",
              "--print-width",
              "140",
              "--use-tabs",
              "false",
              "--single-quote",
              "true",
              "--trailing-comma",
              "es5",
            })
          end
          vim.list_extend(args, { "--stdin-filepath", "$FILENAME" })
          return args
        end,
      }
    end,
  },
}
