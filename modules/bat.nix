{ ... }:
{
  programs.bat = {
    enable = true;
    config.theme = "Catppuccin Mocha";
    themes."Catppuccin Mocha".src = ./catppuccin-mocha.tmTheme;
  };
}
