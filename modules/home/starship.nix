{ ... }:
{
  programs.starship.enable = true;

  # Prompt = Starship's "gruvbox-rainbow" preset, kept as raw TOML under
  # config/starship/ so swapping presets is regenerate-and-rebuild:
  #   starship preset <name> -o config/starship/starship.toml
  # Needs a Nerd Font — JetBrainsMono NF, see modules/fonts.nix.
  programs.starship.settings = builtins.fromTOML (builtins.readFile ../config/starship/starship.toml);
}
