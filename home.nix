{
  ...
}:

{
  # Imported by every host, unconditionally: the dev-only modules below each gate
  # themselves with `lib.mkIf osConfig.local.dev.enable`, so hplaptop (dev off)
  # evaluates all of them to the empty config.
  #
  # Invariant: hplaptop's closure must not change unexplained; a dev-host move must be explained.
  imports = [
    ./modules/home/starship.nix
    ./modules/home/shell.nix
    ./modules/home/bat.nix
    ./modules/home/git.nix
    ./modules/home/lazygit.nix
    ./modules/home/btop.nix
    ./modules/home/fastfetch.nix
    ./modules/home/zellij.nix
    ./modules/home/herdr.nix
    ./modules/home/neovim.nix
    ./modules/home/fonts.nix
    ./modules/home/foot.nix
    ./modules/home/gtk.nix
    ./modules/home/desktop.nix
    ./modules/home/maintenance.nix
    ./modules/home/opencode.nix
    ./modules/home/omp.nix
    ./modules/home/npm.nix
  ];

  # Set once at install; never bump (doc/workflow.md).
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
  programs.bash.enable = true;
}
