{ user, ... }:
{
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      user = {
        name = user.fullName;
        email = user.email;
      };
      init.defaultBranch = "main";
      merge.conflictStyle = "zdiff3";
    };
  };

  # delta is its own module now; enableGitIntegration wires core.pager + interactive.diffFilter
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      dark = true;
      line-numbers = true;
      syntax-theme = "Catppuccin Mocha";
      hyperlinks = true;
    };
  };
}
