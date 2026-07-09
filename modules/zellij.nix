{ pkgs, ... }:
{
  home.packages = [ pkgs.zellij ];
  xdg.configFile."zellij/config.kdl".source = ../config/zellij/config.kdl;
}
