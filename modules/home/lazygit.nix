# delta as lazygit's diff pager.
#
# SCHEMA WARNING — `git.pagers` is correct for the lazygit the locked nixpkgs
# ships (0.61.1) and wrong for lazygit >= 0.64.0, which renamed the key to
# `git.diffRenderers` with a `command` field. Home Manager writes this config
# as a read-only symlink into the nix store, so lazygit's own auto-migration
# CANNOT rewrite it in place — a version bump that crosses 0.64.0 turns into a
# config lazygit rejects rather than one it silently upgrades. Re-check this
# block whenever flake.lock moves nixpkgs; `lazygit --version` on a rebuilt
# host is the check.
{ ... }:
{
  programs.lazygit = {
    enable = true;
    settings = {
      git.pagers = [
        {
          colorArg = "always";
          pager = ''delta --dark --paging=never --line-numbers --hyperlinks --hyperlinks-file-link-format="lazygit-edit://{path}:{line}"'';
        }
      ];
    };
  };
}
