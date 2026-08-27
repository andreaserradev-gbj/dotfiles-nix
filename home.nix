{
  osConfig,
  lib,
  ...
}:

let
  # The full ordered import list, in the EXACT order they appeared before
  # Phase 9. Order is preserved because module merge order is part of the
  # evaluated config structure — reordering imports (even when the SET is
  # identical) changes the derivation hash. Phase 8 added maintenance.nix
  # between desktop.nix and opencode.nix; that position is preserved here.
  devGated = [
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
    ./modules/home/opencode.nix
    ./modules/home/npm.nix
  ];
in
{
  # Imported by every host. The 13 dev-only HM modules are conditional on
  # `osConfig.local.dev.enable` (the same seam as `modules/nixos/dev.nix`):
  # vm + geekom set it true and get the full 16 imports; hplaptop leaves it
  # false and gets only the 3 unconditional ones. The list is built in the
  # original order and filtered in place so the merge order on dev hosts is
  # byte-identical to pre-Phase-9.
  imports = builtins.filter (p: !lib.elem p devGated || osConfig.local.dev.enable) [
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
    ./modules/home/gtk.nix
    ./modules/home/desktop.nix
    ./modules/home/maintenance.nix
    ./modules/home/opencode.nix
    ./modules/home/npm.nix
  ];

  # Set-once: pin state-format defaults to the install release. Never bump casually.
  # Wording matches hosts/vm/default.nix and hosts/geekom/default.nix on purpose —
  # grep the phrase to find all three. This file is imported by every host, so
  # this is the one of the three that moves two drvPaths, not one.
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
  programs.bash.enable = true;
}
