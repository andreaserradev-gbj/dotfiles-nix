{
  lib,
  osConfig,
  user,
  ...
}:
lib.mkIf osConfig.local.dev.enable {
  programs.git = {
    enable = true;
    lfs.enable = true;
    # Machine-wide ignore list, written to ~/.config/git/ignore as a store
    # symlink: edit this list, not that file (an `echo >>` there now fails).
    # `.potetos/` was in the hand-written predecessor and is dropped — it was a
    # decision-trail directory a since-removed skill convention wrote; nothing
    # creates it today.
    ignores = [
      ".dev/"
      ".dev-archive/"
      ".direnv/"
      "**/.claude/settings.local.json"
    ];
    settings = {
      user = {
        name = user.fullName;
        email = user.email;
      };
      init.defaultBranch = "main";
      merge.conflictStyle = "zdiff3";
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      dark = true;
      line-numbers = true;
      # Also reaches lazygit: it shells out to git and delta reads this section.
      # `git add -p` stays unified regardless — interactive.diffFilter is
      # `--color-only`, which delta applies instead of the layout.
      side-by-side = true;
      syntax-theme = "Catppuccin Mocha";
      hyperlinks = true;
    };
  };
}
