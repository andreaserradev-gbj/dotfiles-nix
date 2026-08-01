{ ... }:
{
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "Default"; # btop built-in — no theme file to port
      theme_background = false; # transparent bg (btop default is true)
      shown_boxes = "net proc cpu mem"; # your ordering (default is "cpu mem net proc")
      proc_sorting = "memory"; # default is "cpu lazy"
      save_config_on_exit = false; # EDIT: config is a read-only nix-store symlink → don't self-write
    };
  };
}
