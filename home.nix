{ ... }:

{
  imports = [
    ./modules/home/starship.nix
    ./modules/home/shell.nix
    ./modules/home/bat.nix
    ./modules/home/git.nix
    ./modules/home/lazygit.nix
    ./modules/home/btop.nix
    ./modules/home/fastfetch.nix
    ./modules/home/zellij.nix
    ./modules/home/neovim.nix
    ./modules/home/fonts.nix
    ./modules/home/foot.nix
  ];

  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
  programs.bash.enable = true;
}
