{ lib, osConfig, ... }:
lib.mkIf osConfig.local.dev.enable {
  # npm's update-notifier tells you to run `npm install -g npm@X`, impossible on
  # NixOS (the global prefix is the read-only nodejs store path). It fires on every
  # invocation and the dev-workflow skills parse node/npm output — a parsing
  # hazard, not just noise. Caveat: ~/.npmrc becomes a read-only store symlink, so
  # `npm config set …` fails; add settings here instead.
  home.file.".npmrc".text = ''
    update-notifier=false
  '';
}
