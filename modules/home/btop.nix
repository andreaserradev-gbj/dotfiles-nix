{
  lib,
  osConfig,
  pkgs,
  ...
}:
lib.mkIf osConfig.local.dev.enable {
  programs.btop = {
    enable = true;
    # nixpkgs builds btop without `rocmSupport`, so at runtime btop dlopens
    # librocm_smi64.so, finds none, and logs "AMD GPUs will not be detected":
    # no gpu box, and no GPU line in the cpu box, while `rocm-smi` itself
    # reports temperature, power and busy% fine. `rocmSupport` adds an RPATH
    # to rocm-smi's lib (215 MiB closure) and evaluates only on x86_64, so it
    # is gated to the host that actually runs amdgpu — geekom, the only one
    # setting `hardware.amdgpu.initrd`.
    package =
      if pkgs.stdenv.hostPlatform.isx86_64 && osConfig.hardware.amdgpu.initrd.enable then
        pkgs.btop.override { rocmSupport = true; }
      else
        pkgs.btop;
    settings = {
      color_theme = "Default"; # built-in; no theme file to port
      theme_background = false; # transparent bg
      shown_boxes = "net proc cpu mem";
      proc_sorting = "memory";
      save_config_on_exit = false; # config is a read-only store symlink — don't self-write
    };
  };
}
