{ ... }:
{
  programs.bat = {
    enable = true;
    config.theme = "Catppuccin Mocha";
    themes."Catppuccin Mocha".src = ../config/bat/catppuccin-mocha.tmTheme;
  };
}
