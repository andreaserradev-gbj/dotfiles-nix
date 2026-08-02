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
    ./modules/home/desktop.nix
    ./modules/home/opencode.nix
    ./modules/home/npm.nix
  ];

  # Set-once: pin state-format defaults to the install release. Never bump casually.
  # Wording matches hosts/vm/default.nix and hosts/geekom/default.nix on purpose —
  # grep the phrase to find all three. This file is imported by BOTH hosts, so
  # this is the one of the three that moves two drvPaths, not one.
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
  programs.bash.enable = true;
}
