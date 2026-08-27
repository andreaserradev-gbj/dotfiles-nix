# Non-dev maintenance aliases. Gated on `!osConfig.local.dev.enable` so it is
# inert on the developer hosts (vm, geekom), which get `nh`-based `nrb`/`ngca`
# aliases via `modules/home/shell.nix` instead. On a non-dev host (hplaptop)
# this is the ONLY source of those two aliases: Elisa has no local flake
# checkout, no `nh`, no `nvd` — just raw `nixos-rebuild` against the GitHub
# flake URL and `nix-collect-garbage`.
#
# `programs.bash.enable` in `home.nix` is unconditional (it enables HM's bash
# module, which manages these aliases; it is NOT the user shell). This module
# therefore only needs to populate `programs.bash.shellAliases` — the bash
# module is already active on every host.
#
# `osConfig` is auto-injected because Home Manager runs as a NixOS module
# here, so this needs no extraSpecialArgs wiring in the flake.
{
  osConfig,
  lib,
  ...
}:

lib.mkIf (!osConfig.local.dev.enable) {
  programs.bash.shellAliases = {
    # Build and stage for next boot, fetching the flake from GitHub. No local
    # clone needed — `nixos-rebuild` pulls the flake into the nix store. Elisa
    # runs this after Andrea pushes a change she wants; a reboot activates it.
    nrb = "sudo nixos-rebuild boot --flake github:andreaserradev-gbj/dotfiles-nix";

    # Bulk GC: delete all old generations, reclaim the store, prune the boot
    # menu. Mirrors the dev-host `ngca` alias from shell.nix minus the `nh`
    # dependency — `nix-collect-garbage` (no `--delete-old` flag) deletes
    # everything not reachable from the current generation by default.
    ngca = "sudo nix-collect-garbage && sudo /run/current-system/bin/switch-to-configuration boot";
  };
}
