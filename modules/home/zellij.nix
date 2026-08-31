{
  lib,
  osConfig,
  pkgs,
  ...
}:
lib.mkIf osConfig.local.dev.enable {
  home.packages = [ pkgs.zellij ];
  xdg.configFile."zellij/config.kdl".source = ../../config/zellij/config.kdl;
}
