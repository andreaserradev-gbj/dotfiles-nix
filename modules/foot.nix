{ ... }:
{
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

      # Catppuccin Mocha — matches bat + the Mac. Hex WITHOUT a leading '#'.
      colors-dark = {
        background = "1e1e2e";
        foreground = "cdd6f4";

        regular0 = "45475a"; # black
        regular1 = "f38ba8"; # red
        regular2 = "a6e3a1"; # green
        regular3 = "f9e2af"; # yellow
        regular4 = "89b4fa"; # blue
        regular5 = "f5c2e7"; # magenta
        regular6 = "94e2d5"; # cyan
        regular7 = "bac2de"; # white

        bright0 = "585b70"; # bright black
        bright1 = "f38ba8"; # bright red
        bright2 = "a6e3a1"; # bright green
        bright3 = "f9e2af"; # bright yellow
        bright4 = "89b4fa"; # bright blue
        bright5 = "f5c2e7"; # bright magenta
        bright6 = "94e2d5"; # bright cyan
        bright7 = "a6adc8"; # bright white

        selection-foreground = "cdd6f4";
        selection-background = "45475a";
      };
    };
  };
}
