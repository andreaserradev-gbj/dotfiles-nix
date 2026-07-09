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
    };

    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      DIRENV_LOG_FORMAT = "";
      TODO_DIR = "${config.home.homeDirectory}/.todo";
      CLAUDE_CODE_ENABLE_TASKS = "true";
      CLAUDE_CODE_DISABLE_AUTO_MEMORY = "1";
      CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION = "1";
    };

    initContent = ''
      # fzf navigation helpers
      fcd() { cd "$(find . -type d -not -path '*/.*' | fzf)" && l; }
      fv()  { nvim "$(find . -type f -not -path '*/.*' | fzf)"; }

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
  ];

  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];
}
