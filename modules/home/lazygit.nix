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

    # SCHEMA TRAP: `git.pagers` is rejected from lazygit 0.64.0, which renamed
    # the key to `git.diffRenderers` (the entry's `pager` became `command`). The
    # config is a read-only store symlink, so lazygit cannot auto-migrate it in
    # place — it warns and drops the setting. Re-check on each flake.lock bump.
    settings = {
      # delta renders side-by-side (~/.gitconfig `[delta]`), so the diff panel
      # gets the room: narrower side column, no command log (`@` shows it for
      # the session). Full-screen diff: `0` to focus it, then `+` twice.
      gui.sidePanelWidth = 0.2;
      gui.showCommandLog = false;
      git.diffRenderers = [
        {
          type = "stdinFilter";
          colorArg = "always";
          command = ''delta --dark --paging=never --line-numbers --hyperlinks --hyperlinks-file-link-format="lazygit-edit://{path}:{line}"'';
        }
      ];
    };
  };
}
