{ ... }:

{
  imports = [
    ./modules/starship.nix
    ./modules/shell.nix
    ./modules/bat.nix 
    ./modules/git.nix
  ];

  home.username = "andrea";
  home.homeDirectory = "/home/andrea";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
  programs.bash.enable = true;
}
