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
      syntax-theme = "Catppuccin Mocha";
      hyperlinks = true;
    };
  };
}
