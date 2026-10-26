let
  # The feature registry: where each feature lives, by name. A plain attrset
  # of paths, read as data — not a module system. See doc/dendritic-pattern.md
  # for why the entries must be paths.
  features = import ./features/registry.nix;
in
{
  ...
}:

{
  # Imported by every host, unconditionally: the dev-only modules below each gate
  # themselves with `lib.mkIf osConfig.local.dev.enable`, so hplaptop (dev off)
  # evaluates all of them to the empty config.
  #
  # Invariant: hplaptop's closure must not change unexplained; a dev-host move must be explained.
  #
  # The ORDER is load-bearing: the module system concatenates list-valued
  # contributions in import order. A list-valued registry entry is spliced
  # FLAT with `++` at the position it replaces — never nested inside the list,
  # which is a hard evaluation error ("Module imports can't be nested lists"),
  # not a quiet move.
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
    ./modules/home/ovis.nix
    ./modules/home/neovim.nix
    ./modules/home/fonts.nix
    ./modules/home/foot.nix
  ]
  ++ features.home.desktop
  ++ features.home.niri
  ++ [
    ./modules/home/maintenance.nix
    ./modules/home/omp.nix
    ./modules/home/npm.nix
  ];

  # Set once at install; never bump (doc/workflow.md).
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
  programs.bash.enable = true;
}
