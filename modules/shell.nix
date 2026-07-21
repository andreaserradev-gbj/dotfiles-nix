{
  pkgs,
  config,
  lib,
  ...
}:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true; # replaces the zsh-autosuggestions plugin
    syntaxHighlighting.enable = true; # replaces the /opt/homebrew source line

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "npm"
        "github"
        "docker"
      ]; # dropped: brew, zsh-autosuggestions, aws, mvn
    };

    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
    };

    shellAliases = {
      nv = "nvim"; # nvim lands in 4b — errors only if called meanwhile
      zj = "zellij"; # 4b
      lz = "lazygit"; # 4a
      cls = "clear && fastfetch"; # 4a
      zshconfig = "nvim ~/dotfiles-nix";

      l = "eza --icons"; # eza installed below → works now
      ls = "eza --icons";
      lg = "eza --tree --level=1 --icons --git --git-ignore";
      lg2 = "eza --tree --level=2 --icons --git --git-ignore";
      lg3 = "eza --tree --level=3 --icons --git --git-ignore";
      ll = "eza -lg --icons";

      cdz = "z"; # zoxide installed below

      # --- NixOS / flake (repo = ~/dotfiles-nix, host `nixos`) ---
      nrs = "sudo nixos-rebuild switch --flake ~/dotfiles-nix#nixos"; # apply now + set as boot default
      nrt = "sudo nixos-rebuild test --flake ~/dotfiles-nix#nixos"; # apply now, DON'T touch bootloader → reboot reverts
      nrb = "sudo nixos-rebuild boot --flake ~/dotfiles-nix#nixos"; # stage for next boot, don't apply now
      nfu = "nix flake update --flake ~/dotfiles-nix"; # bump inputs (nixpkgs, home-manager) → rewrites flake.lock
      nfc = "nix flake check ~/dotfiles-nix"; # evaluate/validate the flake without building a system
      nfi = "nix flake init -t ~/dotfiles-nix#devshell"; # initialize a new project
      ngca = "sudo nix-collect-garbage -d && sudo /run/current-system/bin/switch-to-configuration boot"; # bulk: delete ALL old generations, GC, prune boot menu
      # ngl (list), ngd (diff) and ngc (interactive GC) are functions in initContent below, sharing the _gens formatter
      nrp ="nvd diff /run/current-system $(nix build --no-link --print-out-paths ~/dotfiles-nix#nixosConfigurations.nixos.config.system.build.toplevel)"; # preview: what the next nrs will change (run after nfu)
      nixcfg = "cd ~/dotfiles-nix"; # jump to the flake repo
    };

    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      DIRENV_LOG_FORMAT = "";
      TODO_DIR = "${config.home.homeDirectory}/.todo";
    };

    initContent = ''
      # fzf navigation helpers
      fcd() { cd "$(find . -type d -not -path '*/.*' | fzf)" && l; }
      fv()  { nvim "$(find . -type f -not -path '*/.*' | fzf)"; }

      # _gens — aligned generation table (gen · date · kernel · "<- current"),
      # the single source of truth shared by ngl / ngd / ngc.
      _gens() {
        nixos-rebuild list-generations 2>/dev/null | awk '
          NR>1 { printf "%-5s %s %s   kernel %s%s\n", $1, $2, $3, $5, ($8=="True" ? "   <- current" : "") }'
      }
      ngl() { _gens; }   # list generations, formatted like ngd/ngc

      # ngd — nvd generation diff via fzf. Pick ONE generation (diff vs the
      # running system) or TAB two+ (diff oldest vs newest of the picks).
      # Replaces the old last-two-only alias so you can reach any generation.
      ngd() {
        local rows sel gens
        rows=$(_gens)
        sel=$(print -r -- "$rows" | FZF_DEFAULT_OPTS='--height=60% --layout=reverse --border --info=inline' \
              fzf --multi --no-sort \
                  --prompt='diff generation> ' \
                  --header='TAB=mark more  .  1 pick = vs current  .  2+ = oldest vs newest') || return
        [ -n "$sel" ] || return
        gens=(''${(f)"$(print -r -- "$sel" | awk '{print $1}' | sort -n)"})
        if (( ''${#gens} == 1 )); then
          nvd diff /nix/var/nix/profiles/system-''${gens[1]}-link /run/current-system
        else
          nvd diff /nix/var/nix/profiles/system-''${gens[1]}-link /nix/var/nix/profiles/system-''${gens[-1]}-link
        fi
      }

      # ngc — interactive GC. fzf-pick which generations to DELETE (the running
      # gen is never offered), confirm, reclaim the store, prune the boot menu.
      # Bulk "delete all old" lives on the ngca alias.
      ngc() {
        local rows sel gens
        rows=$(_gens | grep -vF -- '<- current')
        [ -n "$rows" ] || { echo "No deletable generations."; return; }
        sel=$(print -r -- "$rows" | FZF_DEFAULT_OPTS='--height=60% --layout=reverse --border --info=inline' \
              fzf --multi --no-sort \
                  --prompt='delete generation> ' \
                  --header='TAB=mark  .  ENTER=delete  .  ESC=cancel  .  current gen is protected') || return
        [ -n "$sel" ] || return
        gens=(''${(f)"$(print -r -- "$sel" | awk '{print $1}')"})
        print -r -- "Delete system generations: $gens"
        read -q "REPLY?Proceed? [y/N] " || { echo; return; }
        echo
        sudo nix-env -p /nix/var/nix/profiles/system --delete-generations $gens &&
        sudo nix-collect-garbage &&
        sudo /run/current-system/bin/switch-to-configuration boot
      }

      # fzf UI styling (from 60-fzf.zsh). Dropped: the missing fzf-preview.sh
      # preview, and the ctrl-r→git-ls-files bind that hijacked history search.
      export FZF_DEFAULT_OPTS="
          --style full
          --border --padding 1,2
          --border-label ' Demo ' --input-label ' Input ' --header-label ' File Type '
          --bind 'result:transform-list-label:
              if [[ -z \$FZF_QUERY ]]; then
                echo \" \$FZF_MATCH_COUNT items \"
              else
                echo \" \$FZF_MATCH_COUNT matches for [\$FZF_QUERY] \"
              fi
              '
          --bind 'focus:+transform-header:file --brief {} || echo \"No file selected\"'
          --color 'border:#aaaaaa,label:#cccccc'
          --color 'list-border:#669966,list-label:#99cc99'
          --color 'input-border:#996666,input-label:#ffcccc'
          --color 'header-border:#6699cc,header-label:#99ccff'
      "
    '';
  };

  # shell-integration tools — the value IS the zsh wiring (folds in plan step 4a-4)
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
  home.packages = [
    pkgs.eza
    pkgs.file
    pkgs.nvd
  ];

  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];
}
