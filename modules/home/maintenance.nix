# Non-dev maintenance aliases — the ONLY source of `nrb`/`ngca` on hplaptop,
# which has no local flake checkout, no `nh` and no `nvd`. The dev hosts (vm,
# geekom) get the `nh`-based aliases from modules/home/shell.nix. HM's bash
# module, enabled unconditionally in home.nix, is what manages these.
{
  osConfig,
  lib,
  user,
  ...
}:

lib.mkIf (!osConfig.local.dev.enable) {
  programs.bash.shellAliases = {
    # `--refresh` is load-bearing: without it nix's 1h tarball cache silently
    # rebuilds a stale commit. The ref is `verified`, not `main` — CI
    # fast-forwards it only after the build matrix goes green (doc/workflow.md).
    nrb = "sudo nixos-rebuild boot --flake ${user.repo}/verified --refresh";

    # Generations are GC roots, so a deleting flag is REQUIRED — plain
    # `nix-collect-garbage` reclaims almost nothing; 14d rather than `-d` keeps
    # rollback targets for the boot menu. switch-to-configuration comes from the
    # PROFILE path, not /run/current-system: after `nrb` that is still the
    # running system, and using it silently un-stages the pending update.
    ngca = "sudo nix-collect-garbage --delete-older-than 14d && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot";
  };
}
