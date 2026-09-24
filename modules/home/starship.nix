{ lib, osConfig, ... }:
lib.mkIf osConfig.local.dev.enable {
  programs.starship.enable = true;

  # Starship's pure-preset, kept as raw TOML under config/starship/ so a preset
  # swap is regenerate-and-rebuild:
  #   starship preset <name> -o config/starship/starship.toml
  programs.starship.settings = builtins.fromTOML (
    builtins.readFile ../../config/starship/starship.toml
  );
}
