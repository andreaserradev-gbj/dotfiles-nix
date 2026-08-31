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
# `osConfig` is auto-injected because Home Manager runs as a NixOS module here,
# so it needs no wiring. `user` does: it reaches HM through
# `home-manager.extraSpecialArgs = { inherit user; }` in flake.nix, the same
# per-host attrset the NixOS modules get.
{
  osConfig,
  lib,
  user,
  ...
}:

lib.mkIf (!osConfig.local.dev.enable) {
  programs.bash.shellAliases = {
    # Build and stage for next boot, fetching the flake from GitHub. No local
    # clone needed — `nixos-rebuild` pulls the flake into the nix store. Elisa
    # runs this after Andrea pushes a change she wants; a reboot activates it.
    # `--refresh` bypasses nix's 1h tarball cache: without it, a push younger
    # than the cache silently rebuilds the STALE commit (hit on site 2026-08-27
    # — three `nrb`s in a row rebuilt the same old generation, "Done" each
    # time). Re-fetching on every run is a few seconds against the GitHub
    # tarball endpoint; a silently stale rebuild is a bug that eats an hour.
    #
    # The ref is `verified`, NOT `main`: CI fast-forwards `verified` only after
    # the build matrix goes green, so a red or still-building `main` simply
    # leaves `verified` where it was and this machine installs nothing new.
    # Pointing it at `main` meant the laptop could fetch a commit CI had not
    # finished checking — a race that used to be patched by a human rule in
    # AGENTS.md and is now closed by mechanism. The URL comes from
    # `user.repo` so a fork updates from its own repo rather than this one.
    nrb = "sudo nixos-rebuild boot --flake ${user.repo}/verified --refresh";

    # Bulk GC: delete old generations, reclaim the store, prune the boot menu.
    # Mirrors the dev-host `ngca` alias from shell.nix minus the `nh`
    # dependency. A generation-deleting flag is REQUIRED: generations are GC
    # roots, so plain `nix-collect-garbage` deletes only unreachable store
    # paths and keeps every old generation alive (verified on-site 2026-08-27
    # — five generations survived a bare run).
    #
    # `--delete-older-than 14d` rather than `-d`: `-d` deletes EVERY old
    # generation, which on the one machine whose recovery story is "pick the
    # previous entry in the boot menu" destroys every rollback target it has.
    # Two weeks keeps a usable window and still reclaims the store.
    #
    # The switch-to-configuration call comes from the PROFILE path, not
    # `/run/current-system`. After `nrb` the two differ: the profile points at
    # the newly staged generation while `/run/current-system` is still the
    # running one. Invoking the RUNNING system's binary rewrites the bootloader
    # with the running system as default — silently un-staging the pending
    # update, so the next reboot comes back on the old system with no error
    # anywhere. The profile's current generation is by definition the intended
    # boot default, so this prunes deleted entries without ever discarding a
    # staged one. Exactly the `nrb`-then-reboot workflow this host documents.
    ngca = "sudo nix-collect-garbage --delete-older-than 14d && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot";
  };
}
