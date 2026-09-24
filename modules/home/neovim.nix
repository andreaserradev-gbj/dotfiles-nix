{
  pkgs,
  config,
  lib,
  osConfig,
  ...
}:

lib.mkIf osConfig.local.dev.enable {
  # Neovim + LazyVim, ported as a verbatim managed-file lua tree: lazy.nvim
  # bootstraps and clones plugins at runtime, so the tree is copied as-is rather
  # than rewritten as Nix. Editor via home.packages, NOT programs.neovim — that
  # writes its own ~/.config/nvim/init.lua and collides with the tree below.

  home.packages = with pkgs; [
    neovim

    # LazyVim's runtime deps, expected on PATH; git comes from the git module.
    ripgrep
    fd
    gcc # nvim-treesitter builds parsers at runtime
    tree-sitter

    # LSP servers, Nix-provided instead of Mason (why: the nix-ld note in
    # modules/nixos/dev.nix). Names must match nvim-lspconfig's launchers:
    # bashls -> bash-language-server, cssls/html/jsonls ->
    # vscode-langservers-extracted, yamlls -> yaml-language-server, lua_ls ->
    # lua-language-server, marksman, vtsls -> vtsls (bundles its own node).
    bash-language-server
    vscode-langservers-extracted
    yaml-language-server
    lua-language-server
    marksman
    vtsls
    nil

    # Formatters, resolved from PATH by conform.nvim.
    prettier
    shfmt
    stylua
    nixfmt
    statix
  ];

  # vim.loader's luac cache keys on mtime/size, which Nix pins — wipe it each
  # activation so the next launch recompiles (doc/troubleshooting.md).
  home.activation.clearNvimByteCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run rm -rf "${config.xdg.cacheHome}/nvim/luac"
  '';

  # LazyVim config tree, verbatim from the repo root's config/nvim/ — symlinked
  # into ~/.config/nvim. Flakes only see git-tracked files (`git add config/nvim`
  # before switching); lazy.nvim's lockfile goes to the writable state dir and is
  # intentionally not committed (see lua/config/lazy.lua).
  xdg.configFile."nvim".source = ../../config/nvim;
}
