{ lib, osConfig, ... }:
lib.mkIf osConfig.local.dev.enable {
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "Default"; # built-in; no theme file to port
      theme_background = false; # transparent bg
      shown_boxes = "net proc cpu mem";
      proc_sorting = "memory";
      save_config_on_exit = false; # config is a read-only store symlink — don't self-write
    };
  };
}
