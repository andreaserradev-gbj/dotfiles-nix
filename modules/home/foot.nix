{ lib, osConfig, ... }:
lib.mkIf osConfig.local.dev.enable {
  programs.foot = {
    enable = true;

    settings = {
      main = {
        font = "JetBrainsMono Nerd Font:size=12, DejaVu Sans:size=12";
        dpi-aware = "no";
        pad = "8x8";
        login-shell = "yes";
      };

      scrollback.lines = 10000;

      cursor = {
        style = "block";
        blink = "no";
      };

      mouse.hide-when-typing = "yes";

      # Render Nerd Font glyphs at their widest cell so icons/powerline don't clip.
      tweak.grapheme-width-method = "max";

      # Catppuccin Mocha (matches bat + the Mac); hex values take NO leading '#'.
      colors-dark = {
        background = "1e1e2e";
        foreground = "cdd6f4";

        regular0 = "45475a";
        regular1 = "f38ba8";
        regular2 = "a6e3a1";
        regular3 = "f9e2af";
        regular4 = "89b4fa";
        regular5 = "f5c2e7";
        regular6 = "94e2d5";
        regular7 = "bac2de";

        bright0 = "585b70";
        bright1 = "f38ba8";
        bright2 = "a6e3a1";
        bright3 = "f9e2af";
        bright4 = "89b4fa";
        bright5 = "f5c2e7";
        bright6 = "94e2d5";
        bright7 = "a6adc8";

        selection-foreground = "cdd6f4";
        selection-background = "45475a";
      };
    };
  };
}
