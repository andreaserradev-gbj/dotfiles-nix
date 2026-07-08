{ pkgs, ... }:

{
  home.username = "andrea";
  home.homeDirectory = "/home/andrea";

  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
  programs.bash.enable = true;

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      character = {
        success_symbol = "[λ](bold purple)";
        error_symbol = "[λ](bold red)";
      };
    };
  };
}
