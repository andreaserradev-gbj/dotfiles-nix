# lazygit + delta as its diff pager. Same dev gate as the other dev-only HM
# modules: hplaptop never sees lazygit or wl-clipboard.
{
  lib,
  osConfig,
  pkgs,
  ...
}:
lib.mkIf osConfig.local.dev.enable {
  # lazygit's `y` and nvim's local `"+` register both resolve wl-copy/wl-paste
  # through PATH; over SSH nvim uses OSC 52 instead (config/nvim options.lua).
  home.packages = [ pkgs.wl-clipboard ];

  programs.lazygit = {
    enable = true;

    # SCHEMA TRAP: `git.pagers` is the key the locked lazygit accepts; lazygit >=
    # 0.64.0 renamed it to `git.diffRenderers`. The config is a read-only store
    # symlink, so lazygit cannot auto-migrate it in place — a nixpkgs bump across
    # that boundary yields a config lazygit rejects. Re-check on each flake.lock
    # bump.
    settings = {
      git.pagers = [
        {
          colorArg = "always";
          pager = ''delta --dark --paging=never --line-numbers --hyperlinks --hyperlinks-file-link-format="lazygit-edit://{path}:{line}"'';
        }
      ];
    };
  };
}
