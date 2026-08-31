{ lib, osConfig, ... }:
lib.mkIf osConfig.local.dev.enable {
  programs.starship.enable = true;

  # Prompt = Starship's "pure-preset" (the Pure prompt), kept as raw TOML under
  # config/starship/ so swapping presets is regenerate-and-rebuild:
  #   starship preset <name> -o config/starship/starship.toml
  # Pure needs no Nerd Font — it uses plain Unicode glyphs. JetBrainsMono NF is
  # installed anyway (modules/home/fonts.nix) for the rest of the TUI stack, and
  # a preset that DOES need it (e.g. gruvbox-rainbow) would work as a drop-in.
  programs.starship.settings = builtins.fromTOML (
    builtins.readFile ../../config/starship/starship.toml
  );
}
