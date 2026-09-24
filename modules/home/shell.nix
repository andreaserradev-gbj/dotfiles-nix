{
  pkgs,
  config,
  lib,
  osConfig,
  user,
  ...
}:
let
  repoName = "dotfiles-nix";
  repo = "~/${repoName}"; # ~ must stay literal: the aliases expand it at runtime
  repoAbs = "${config.home.homeDirectory}/${repoName}"; # NH_FLAKE needs an absolute path

  # Flags `nrs`/`nrt` carry on hosts with the loopback seam on (geekom): a
  # switch's phase 1 can restart the display stack and kill the session that
  # launched it, while an activation under sshd is outside that scope (the seam
  # is owned by modules/nixos/loopback-rebuild.nix).
  #
  # --hostname is REQUIRED, not redundant: with --target-host set, nh otherwise
  # derives the flake attribute from the target ("localhost"), which is not a
  # nixosConfiguration here. nh reads the remote sudo password locally and pipes
  # it over stdin, so no TTY juggling.
  loop = lib.optionalString osConfig.local.loopbackRebuild.enable " --target-host ${user.username}@localhost --hostname ${osConfig.networking.hostName}";

  # config/zsh/_pnpm is pnpm's shipped completion with the ~50 global flags
  # filtered out — they buried the package.json script names — and it explains
  # itself; shipping our own copy also drops the pkgs.pnpm build dependency. It
  # still has to be installed into fpath here: a dev shell only puts pnpm on PATH
  # and never touches fpath, so the completion would never be reachable.
  pnpmZshCompletion = pkgs.runCommand "pnpm-zsh-completion" { } ''
    install -Dm444 ${../../config/zsh/_pnpm} "$out/share/zsh/site-functions/_pnpm"
  '';
in
lib.mkIf osConfig.local.dev.enable {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "npm"
        "docker"
      ];
    };

    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
    };

    shellAliases = {
      nv = "nvim";
      zj = "zellij";
      hd = "herdr";
      lz = "lazygit";
      cls = "clear && fastfetch";
      zshconfig = "nvim ${repo}/modules/home/shell.nix"; # the file this shell IS; `nixcfg` = the whole repo

      l = "eza --icons";
      lg = "eza --tree --level=1 --icons --git --git-ignore";
      lg2 = "eza --tree --level=2 --icons --git --git-ignore";
      lg3 = "eza --tree --level=3 --icons --git --git-ignore";
      ll = "eza -lg --icons";

      # --- NixOS / flake (repo = ~/dotfiles-nix; host = the local hostname) ---
      # Rebuilds and GC go through nh (programs.nh below); raw nixos-rebuild still works.
      nrb = "nh os boot";
      nrp = "nh os build";
      nrs = "nh os switch --ask${loop}";
      nrt = "nh os test${loop}";
      nfu = "nix flake update --flake ${repo}";
      nfb = "${repo}/scripts/nfb.sh";
      nfc = "nix flake check ${repo}";
      nfi = "nix flake init -t ${repo}#devshell";
      nfp = "nix flake init -t ${repo}#python-devshell";
      # Bulk GC (keep newest), then prune the boot menu. The pruning call comes
      # from the PROFILE path, never `/run/current-system`: after `nrb` stages a
      # generation the running system's binary rewrites the bootloader with ITSELF
      # as default — silently discarding the staged update, no error anywhere.
      # The same rule, with the hplaptop alias, is in modules/home/maintenance.nix.
      ngca = "nh clean all && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot";
      # ngl (list), ngd (diff) and ngc (interactive GC) are functions in
      # initContent below, sharing the _gens formatter.
      nixcfg = "cd ${repo}";
      speedtest = "NIXPKGS_ALLOW_UNFREE=1 nix run --impure nixpkgs#ookla-speedtest -- --accept-license --accept-gdpr"; # unfree per-invocation, not a global predicate
    };

    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      DIRENV_LOG_FORMAT = "";
    };

    # NOTE — everything inside this `initContent` string is literal .zshrc text,
    # comments included: adding a line here CHANGES the derivation, it is not a
    # free annotation the way a Nix comment (like this one) is.
    #
    # DO NOT COPY THE SECRET-EXPORT PATTERN BELOW FOR A HIGHER-VALUE SECRET:
    # exporting one puts it in every child process's environ, readable via
    # /proc/<pid>/environ and leaked by anything that dumps the environment (a
    # crash reporter, `env` in a pasted bug report, a CI log). It is acceptable
    # for a low-value, rate-limit-scoped key; anything else — SSH keys, cloud
    # tokens, passwords — belongs in /run/secrets, read at the point of use.
    initContent = ''
      # CONTEXT7_API_KEY — runtime secret for the context7 MCP server
      # (modules/home/opencode.nix reads it via {env:...}). Provisioned by
      # sops-nix on dev-enabled hosts only: the guard keeps shells quiet where the
      # secret is not provisioned yet, and opencode falls back to anonymous mode.
      export CONTEXT7_API_KEY="$(cat /run/secrets/CONTEXT7_API_KEY 2>/dev/null)"

      # TYPESAFE_API_KEY — runtime secret for ~/code/typesafe-lab's `real`
      # provider (src/typesafe/real.ts reads it from the env). Same provisioning
      # and same guard as CONTEXT7_API_KEY above; the consumer's loadEnvInto
      # (src/cli.ts) only fills vars NOT already in the environment, so this
      # export wins over the project's .env.
      export TYPESAFE_API_KEY="$(cat /run/secrets/TYPESAFE_API_KEY 2>/dev/null)"

      # fzf navigation helpers
      fcd() { cd "$(find . -type d -not -path '*/.*' | fzf)" && l; }
      fv()  { nvim "$(find . -type f -not -path '*/.*' | fzf)"; }

      # _gens — aligned generation table (gen · date · kernel · "<- current"),
      # the single source of truth shared by ngl / ngd / ngc.
      _gens() {
        nixos-rebuild list-generations 2>/dev/null | awk '
          NR>1 { printf "%-5s %s %s   kernel %s%s\n", $1, $2, $3, $5, ($8=="True" ? "   <- current" : "") }'
      }
      ngl() { _gens; }

      # nfud — the dry-run twin of nfu: resolve every input, write the would-be
      # flake.lock to a temp file, print what moved, discard it. `nix flake
      # update` accepts no --dry-run and no --no-write-lock-file;
      # --output-lock-file is the supported equivalent. The exit status IS the
      # answer: 0 = nothing would move, 1 = something would, 2 = the resolution
      # itself failed. The per-node summary leads because a raw lock diff shows
      # rev and narHash edits without naming the input they belong to.
      nfud() {
        local tmp rc
        tmp=$(mktemp -t nfud.XXXXXX) || return 2
        if ! nix flake update --flake "${repoAbs}" --output-lock-file "$tmp"; then
          rm -f "$tmp"
          print -ru2 -- 'nfud: input resolution failed'
          return 2
        fi
        jq -rn --slurpfile o "${repoAbs}/flake.lock" --slurpfile n "$tmp" '
          def short: if . == null then "-" else .[0:7] end;
          ($o[0].nodes) as $O | ($n[0].nodes) as $N
          | [($O | keys[]), ($N | keys[])] | unique[]
          | . as $k
          | select(($O[$k].locked.rev // "") != ($N[$k].locked.rev // ""))
          | "\($k): \($O[$k].locked.rev | short) -> \($N[$k].locked.rev | short)"
        '
        diff -u "${repoAbs}/flake.lock" "$tmp"
        rc=$?
        rm -f "$tmp"
        case $rc in
          0) print -r -- 'nfud: no input would move'; return 0 ;;
          1) return 1 ;;
          *) print -ru2 -- "nfud: diff failed (rc=$rc)"; return 2 ;;
        esac
      }

      # _pick_gens ROWS PROMPT HEADER — fzf-multi-pick from ROWS; prints the
      # chosen generation numbers (one per line, sorted). Shared by ngd and ngc.
      _pick_gens() {
        print -r -- "$1" | FZF_DEFAULT_OPTS='--height=60% --layout=reverse --border --info=inline' \
          fzf --multi --no-sort --prompt="$2" --header="$3" | awk '{print $1}' | sort -n
      }

      # ngd — nvd generation diff via fzf. Pick ONE generation (diff vs the
      # running system) or TAB two+ (diff oldest vs newest of the picks).
      ngd() {
        local sel gens
        sel=$(_pick_gens "$(_gens)" 'diff generation> ' 'TAB=mark more  .  1 pick = vs current  .  2+ = oldest vs newest')
        [ -n "$sel" ] || return
        gens=("''${(@f)sel}")
        if (( ''${#gens} == 1 )); then
          nvd diff /nix/var/nix/profiles/system-''${gens[1]}-link /run/current-system
        else
          nvd diff /nix/var/nix/profiles/system-''${gens[1]}-link /nix/var/nix/profiles/system-''${gens[-1]}-link
        fi
      }

      # ngc — interactive GC. fzf-pick which generations to DELETE (the running
      # gen is never offered), confirm, reclaim the store, prune the boot menu
      # from the profile path for the reason on the ngca alias above.
      ngc() {
        local rows sel gens
        rows=$(_gens | grep -vF -- '<- current')
        [ -n "$rows" ] || { echo "No deletable generations."; return; }
        sel=$(_pick_gens "$rows" 'delete generation> ' 'TAB=mark  .  ENTER=delete  .  ESC=cancel  .  current gen is protected')
        [ -n "$sel" ] || return
        gens=("''${(@f)sel}")
        print -r -- "Delete system generations: $gens"
        read -q "REPLY?Proceed? [y/N] " || { echo; return; }
        echo
        sudo nix-env -p /nix/var/nix/profiles/system --delete-generations $gens &&
        sudo nix-collect-garbage &&
        sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot
      }

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

  # nh — nicer nixos-rebuild/GC front-end, backing the nr*/ngca aliases above.
  # NH_FLAKE (set from `flake`) lets `nh os …` run with no path/host args.
  programs.nh = {
    enable = true;
    flake = repoAbs;
  };

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
    # GitHub CLI — PR-first workflow against this repo (branch → PR → CI → merge),
    # dev-gated with the rest of shell.nix so hplaptop needs neither PRs nor the
    # ~/.config/gh auth state it would drop there.
    pkgs.gh
    pkgs.file
    pkgs.nvd
    pnpmZshCompletion
  ];

  # compinit caches its fpath scan in ~/.zcompdump-* and decides freshness by
  # mtime, but Nix pins every store mtime to 1970, so a newly added completion
  # stays invisible and Tab silently does nothing (same failure mode as the nvim
  # luac cache). Wipe it on every activation; the next shell rebuilds it.
  home.activation.clearZshCompdump = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run rm -f "${config.home.homeDirectory}"/.zcompdump*
  '';

  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];
}
