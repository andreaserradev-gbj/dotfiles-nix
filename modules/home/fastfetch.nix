{
  lib,
  osConfig,
  pkgs,
  ...
}:
lib.mkIf osConfig.local.dev.enable {
  home.packages = [ pkgs.fastfetch ];
  xdg.configFile."fastfetch/config.jsonc".source = ../../config/fastfetch/config.jsonc;
}
