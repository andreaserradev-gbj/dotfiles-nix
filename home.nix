{ ... }:

{
  imports = [
    ./modules/starship.nix
    ./modules/shell.nix
    ./modules/bat.nix
    ./modules/git.nix
    ./modules/lazygit.nix
    ./modules/btop.nix
    ./modules/fastfetch.nix
    ./modules/zellij.nix
    ./modules/neovim.nix
    ./modules/fonts.nix
    ./modules/foot.nix
  ];

  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
  programs.bash.enable = true;
}
