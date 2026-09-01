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
#
# This module also owns wl-clipboard, so it is dev-gated like lazygit itself.
# Pressing `y` here runs lazygit's vendored atotto/clipboard library
# (vendor/github.com/atotto/clipboard/clipboard_unix.go), which probes for
# wl-copy+wl-paste whenever WAYLAND_DISPLAY is set — then xclip — then xsel —
# and reports "No clipboard utilities available" when it finds none, which was
# the state of every host before this line. Terminal Ctrl+Shift+C still worked
# through all of it because the terminal emulator owns its own clipboard and
# never calls out to these tools. On the VM the same package is what nvim's
# local-session `"+` register needs (LazyVim sets `clipboard = unnamedplus`
# when SSH_TTY is unset, and the register resolves through PATH like
# lazygit's); over SSH the OSC 52 path in config/nvim options.lua keeps
# covering it instead, and wl-copy is simply inert. hplaptop (dev gate off)
# never sees the package — GNOME apps manage the clipboard themselves.
{
  lib,
  osConfig,
  pkgs,
  ...
}:
lib.mkIf osConfig.local.dev.enable {
  home.packages = [ pkgs.wl-clipboard ];

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
