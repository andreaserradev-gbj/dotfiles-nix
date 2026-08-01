{ ... }:
{
  # npm's update-notifier prints "New major version of npm available! ...
  # To update run: npm install -g npm@X" on stderr. On NixOS that advice is
  # IMPOSSIBLE to follow: npm's global prefix is the read-only nodejs store
  # path, so the suggested command always fails. npm's version is whatever
  # pkgs.nodejs bundles and moves only when nodejs moves.
  #
  # Silencing it is not just tidiness — the notice goes to stderr on every npm
  # invocation, and the dev-workflow skills parse the output of node/npm
  # scripts. Stray notices are a parsing hazard, not only noise.
  #
  # Caveat, same shape as btop.nix's `save_config_on_exit = false`: this makes
  # ~/.npmrc a read-only store symlink, so `npm config set …` will fail. Add
  # settings here instead.
  home.file.".npmrc".text = ''
    update-notifier=false
  '';
}
