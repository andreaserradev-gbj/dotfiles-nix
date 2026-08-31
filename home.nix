{
  ...
}:

{
  # Imported by every host, unconditionally. The 13 dev-only HM modules gate
  # THEMSELVES, each wrapping its own body in
  # `lib.mkIf osConfig.local.dev.enable` — the same idiom gtk.nix and
  # desktop.nix already used for the desktop seam, and the same option
  # `modules/nixos/dev.nix` keys off. vm + geekom set it true; hplaptop leaves
  # it false and evaluates those 13 to the empty config.
  #
  # A `mkIf false` module contributes nothing to the result, so importing it on
  # hplaptop is equivalent to not importing it. That equivalence is not assumed
  # — it is the gate on this change: hplaptop's drvPath was byte-identical
  # (384g95mc1wz7cshinrbp3sy4jp5i1mr0) before and after the list below stopped
  # being filtered.
  #
  # The standing invariant is NOT "no drvPath ever moves". It is: hplaptop's
  # closure must not change unexplained, and a dev-host move must be explained
  # — an empty `nvd diff` is what "explained" means here.
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
    ./modules/home/gtk.nix
    ./modules/home/desktop.nix
    ./modules/home/maintenance.nix
    ./modules/home/opencode.nix
    ./modules/home/npm.nix
  ];

  # Set-once: pin state-format defaults to the install release. Never bump casually.
  # Wording matches hosts/vm/default.nix, hosts/geekom/default.nix and
  # hosts/hplaptop/default.nix on purpose — grep "Set-once" to find all four.
  # The other three are `system.stateVersion`, one per host; this is the
  # `home.stateVersion`, and home.nix is imported by every host, so this is the
  # one of the four that moves all three drvPaths rather than just its own.
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;
  programs.bash.enable = true;
}
