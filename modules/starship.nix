{ ... }:
{
  programs.starship.enable = true;

  # Default directory.read_only is 🔒 (U+1F512, emoji) → tofu without an emoji
  # font. Use the Nerd Font lock  (U+F023, in JetBrainsMono NF) so it renders
  # and matches the icon-font prompt. COPY-PASTE this line — the glyph can't be typed.
  programs.starship.settings.directory.read_only = builtins.fromJSON ''" \uf023"'';
}
