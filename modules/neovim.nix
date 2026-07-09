{ pkgs, ... }:

{
  # Neovim + LazyVim, ported as a verbatim managed-file lua tree.
  #
  # Style: managed-file, not native. LazyVim owns its own plugin manager
  # (lazy.nvim bootstraps + clones plugins at runtime), so we copy the config
  # tree verbatim instead of rewriting it as Nix.
  #
  # Editor installed via home.packages, NOT programs.neovim, on purpose:
  # programs.neovim writes its own ~/.config/nvim/init.lua, which collides with
  # the verbatim xdg.configFile."nvim" tree below (HM errors on the duplicate).

  home.packages = with pkgs; [
    neovim

    # LazyVim runtime deps it expects on PATH (omanix's installCoreDependencies
    # equivalent). git is already provided by the git module, so it's not repeated.
    ripgrep # grep picker
    fd # file picker
    gcc # nvim-treesitter compiles parsers at runtime
    tree-sitter # treesitter CLI

    # LSP servers — Nix-provided instead of Mason (Mason's prebuilt binaries
    # assume an FHS layout and break on NixOS). Binary names match what
    # nvim-lspconfig launches:
    #   bashls -> bash-language-server
    #   cssls / html / jsonls -> vscode-langservers-extracted
    #   yamlls -> yaml-language-server
    #   lua_ls -> lua-language-server
    #   marksman -> marksman
    #   vtsls -> vtsls  (TypeScript; bundles its own node, no global node needed)
    bash-language-server
    vscode-langservers-extracted
    yaml-language-server
    lua-language-server
    marksman
    vtsls

    # Formatters (conform.nvim, PATH-resolved). node arrives transitively via the
    # node-based servers/prettier — no global node or nvm needed. (prettier is
    # top-level in nixpkgs 26.05; the old nodePackages set was removed.)
    prettier
    shfmt
    stylua
    nixfmt # nix formatter (RFC-style official; conform maps nix -> nixfmt)
  ];

  # LazyVim config tree, copied verbatim from the repo root's config/nvim/.
  # Whole-dir symlink into ~/.config/nvim. Flakes only see git-tracked files, so
  # `git add config/nvim` before switching. lazy.nvim's lockfile is redirected to
  # the writable state dir (see lua/config/lazy.lua) and intentionally not committed.
  xdg.configFile."nvim".source = ../config/nvim;
}
