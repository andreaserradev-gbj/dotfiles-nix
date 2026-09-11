{
  pkgs,
  config,
  lib,
  osConfig,
  user,
  ...
}:
let
  repoName = "dotfiles-nix"; # single source for the flake repo dir
  repo = "~/${repoName}"; # shell aliases (~ expanded at runtime)
  repoAbs = "${config.home.homeDirectory}/${repoName}"; # NH_FLAKE needs an absolute path

  # pnpm's shipped zsh completion is a thin dispatcher around `pnpm
  # completion-server` that hands the server's entire reply -- ~50 global flags
  # plus the package.json scripts -- to _describe, so `pnpm run <TAB>` buries
  # the script names. config/zsh/_pnpm is that dispatcher with the flags
  # filtered out; it explains itself. Shipping our own copy also drops the
  # build-time dependency on pkgs.pnpm.
  #
  # It still has to be installed into fpath here: a dev shell only puts pnpm on
  # PATH and never touches fpath, so a completion file would otherwise never be
  # reachable. Autoloaded at Tab time, which also sidesteps direnv activating
  # after zsh has already sourced its config.
  pnpmZshCompletion = pkgs.runCommand "pnpm-zsh-completion" { } ''
    install -Dm444 ${../../config/zsh/_pnpm} "$out/share/zsh/site-functions/_pnpm"
  '';
in
lib.mkIf osConfig.local.dev.enable {
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
      zshconfig = "nvim ${repo}/modules/home/shell.nix"; # the file this shell IS; `nixcfg` covers the whole repo

      l = "eza --icons"; # eza installed below → works now
      lg = "eza --tree --level=1 --icons --git --git-ignore";
      lg2 = "eza --tree --level=2 --icons --git --git-ignore";
      lg3 = "eza --tree --level=3 --icons --git --git-ignore";
      ll = "eza -lg --icons";

      cdz = "z"; # zoxide installed below

      # --- NixOS / flake (repo = ~/dotfiles-nix; host = the local hostname) ---
      # Rebuilds/GC go through nh (see programs.nh below): automatic nvd diff, sudo
      # self-elevation, host+flake auto-detected via NH_FLAKE. Raw nixos-rebuild still works.
      # nrs/nrt are DELIBERATELY NOT shellAliases. HM 26.05 emits
      # shellAliases AFTER initContent in the generated .zshrc, and zsh
      # resolves a name by its LAST definition — an alias here would shadow
      # both the base functions and geekom's loopback override defined in
      # initContent (verified 2026-09-11: `whence -v nrs` resolved the alias
      # while the loopback function sat earlier in the same file). The
      # functions live in initContent, where ordering is controllable; the
      # loopback fragment re-defines them on geekom, later in that same
      # stream, so the override wins under any emission order.
      nrb = "nh os boot"; # build + stage for next boot, don't activate now
      nrp = "nh os build"; # preview: build + diff vs current, no activation (run after nfu)
      nfu = "nix flake update --flake ${repo}"; # bump inputs (nixpkgs, home-manager) → rewrites flake.lock
      nfc = "nix flake check ${repo}"; # evaluate/validate the flake without building a system
      nfi = "nix flake init -t ${repo}#devshell"; # initialize a new project (node-flavored default)
      nfp = "nix flake init -t ${repo}#python-devshell"; # initialize a Python project (uv + python3)
      # Bulk GC (keep newest), then prune the boot menu. The pruning call comes
      # from the PROFILE path, never `/run/current-system`: after `nrb` stages a
      # generation the two differ, and the running system's binary rewrites the
      # bootloader with ITSELF as default — silently discarding the staged
      # update, no error anywhere. The profile's current generation is by
      # definition the intended boot default.
      ngca = "nh clean all && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot";
      # ngl (list), ngd (diff) and ngc (interactive GC) are functions in initContent below, sharing the _gens formatter
      nixcfg = "cd ${repo}"; # jump to the flake repo
      speedtest = "NIXPKGS_ALLOW_UNFREE=1 nix run --impure nixpkgs#ookla-speedtest -- --accept-license --accept-gdpr"; # one-shot Ookla speedtest (unfree → per-invocation allow, not added to predicate)
    };

    # Loopback rebuild target, read by the nrs/nrt fragment appended to
    # initContent below. Set only on hosts with the seam on (geekom); unset
    # on the rest — the VM keeps plain aliases (it is normally rebuilt over
    # SSH from outside anyway) and hplaptop has no sshd and never loads
    # this file. Taken from the host's own identity attrset rather than
    # hardcoded so a fork editing user.nix needs no shell.nix edit.
    sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      DIRENV_LOG_FORMAT = "";
      TODO_DIR = "${config.home.homeDirectory}/.todo";
    }
    // lib.optionalAttrs (osConfig.local.loopbackRebuild.enable or false) {
      NH_LOOPBACK_TARGET = "${user.username}@localhost";
    };

    # NOTE — everything inside this `initContent` string is literal .zshrc text,
    # comments included. Adding a line here CHANGES the derivation; it is not a
    # free annotation the way a Nix comment (like this one) is.
    #
    # DO NOT COPY THE CONTEXT7_API_KEY PATTERN BELOW FOR A HIGHER-VALUE SECRET.
    # Exporting a secret into the shell environment puts it in every child
    # process's environ, readable via /proc/<pid>/environ and leaked by anything
    # that dumps the environment (a crash reporter, `env` in a pasted bug report,
    # a CI log). It is acceptable for a context7 key, which is low-value and
    # rate-limit-scoped. Anything else — SSH keys, cloud tokens, passwords —
    # should stay a file under /run/secrets and be read at the point of use.
    initContent = ''
      # CONTEXT7_API_KEY — runtime secret for the context7 MCP server
      # (modules/home/opencode.nix reads it via {env:...} interpolation).
      # Provisioned by sops-nix on dev-enabled hosts only (modules/nixos/dev.nix
      # declares it; home.nix already gates shell.nix off hplaptop, so this
      # export never even loads on a non-recipient machine). The guard keeps
      # shells quiet on rebuilds where the secret is not provisioned yet
      # (fresh host before its first rebuild, or a host that was never a
      # recipient) — the variable is simply empty and opencode falls back to
      # anonymous mode / lower rate limits.
      export CONTEXT7_API_KEY="$(cat /run/secrets/CONTEXT7_API_KEY 2>/dev/null)"

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

      # nrs/nrt as FUNCTIONS, not shellAliases. Reason lives on the
      # loopbackRebuild fragment below: HM 26.05 emits shellAliases AFTER
      # initContent, so any alias defined in the shellAliases block lands
      # after a loopback override function and shadows it (verified on
      # geekom). Functions here put both hosts' behavior in one ordered
      # stream: this base pair stands on every host, and the loopback
      # fragment (geekom only) re-defines them targeting localhost — later
      # definitions win, so the override is the whole mechanism. Behavior is
      # identical to the aliases they replace (same nh invocation, --ask).
      nrs() { nh os switch --ask "$@"; }
      nrt() { nh os test "$@"; }

      # _pick_gens ROWS PROMPT HEADER — fzf-multi-pick from ROWS; prints the
      # chosen generation numbers (one per line, sorted). Shared by ngd and ngc.
      _pick_gens() {
        print -r -- "$1" | FZF_DEFAULT_OPTS='--height=60% --layout=reverse --border --info=inline' \
          fzf --multi --no-sort --prompt="$2" --header="$3" | awk '{print $1}' | sort -n
      }

      # ngd — nvd generation diff via fzf. Pick ONE generation (diff vs the
      # running system) or TAB two+ (diff oldest vs newest of the picks).
      # Replaces the old last-two-only alias so you can reach any generation.
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
      # gen is never offered), confirm, reclaim the store, prune the boot menu.
      # Bulk "delete all old" lives on the ngca alias. The boot-menu prune uses
      # the profile path for the reason spelled out on that alias.
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
    ''
    # Loopback rebuilds — appended only on hosts with the seam on (geekom):
    # phase 1 of a switch can restart the display stack, killing the session
    # that launched it; running the activation through SSH to localhost puts
    # it inside sshd's scope, which no display restart can reap. Concatenated
    # as its own string (NOT interpolated into the one above) so nixfmt's
    # reindentation of the base string cannot alter this file's output on
    # hosts without the seam. The seam (modules/nixos/loopback-rebuild.nix)
    # pins localhost's host key and authorizes this machine's own user key,
    # so no manual ssh-keyscan dance.
    #
    # ORDER IS THE WHOLE GAME here, and it is inverted from what HM's option
    # name suggests:
    #   * HM 26.05 emits `shellAliases` AFTER `initContent` in the generated
    #     .zshrc (verified on geekom 2026-09-11: initContent landed at line
    #     ~119-145, shellAliases at ~164-185). A plain `alias nrs=...` from
    #     the shellAliases block therefore lands AFTER any function defined
    #     here, and zsh resolves the LATER definition: `whence -v nrs`
    #     reported the plain alias even though the loopback function existed.
    #     A trailing `unalias` inside initContent is equally defeated — it
    #     runs BEFORE HM's alias emission.
    #
    # The fix that actually holds: since the loopback functions must win, the
    # base initContent (the string above this fragment) declares plain nrs/nrt
    # as FUNCTIONS for every host, and this loopback fragment OVERRIDES those
    # functions (later in the same initContent stream). No HM alias for nrs/nrt
    # exists anymore (the shellAliases entries were removed and replaced by
    # the function declarations), so nothing later in the file can shadow the
    # loopback functions. `--ask` behavior is preserved: nh prompts before
    # activating either way.
    + lib.optionalString (osConfig.local.loopbackRebuild.enable or false) ''
      # Loopback nrs/nrt — overrides the base functions above; runs activation
      # over SSH to localhost so phase 1 cannot be reaped by a display-stack
      # restart (the full reasoning sits above this string). --hostname is
      # REQUIRED: with --target-host set, nh otherwise derives the flake
      # attribute from the target ("localhost"), which does not exist in
      # nixosConfigurations. nh prompts for the remote sudo password locally
      # and feeds it over stdin, so no TTY juggling. Escape hatch if sshd is
      # ever broken: `nh os switch --ask` directly (the plain function
      # behavior), or nrb + reboot.
      nrs() { nh os switch --ask --target-host "$NH_LOOPBACK_TARGET" --hostname "$HOST" "$@"; }
      nrt() { nh os test --target-host "$NH_LOOPBACK_TARGET" --hostname "$HOST" "$@"; }
    '';
  };

  # nh — nicer nixos-rebuild/GC front-end, backs the nr*/ngca aliases above.
  # NH_FLAKE (set from `flake`) lets `nh os …` run with no path/host args.
  programs.nh = {
    enable = true;
    flake = repoAbs;
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
    # GitHub CLI: PR-first workflow against this repo (branch → PR → CI runs
    # on the PR → merge). Dev-gated with the rest of shell.nix — Elisa's
    # hplaptop needs neither PRs nor the auth state it drops in
    # ~/.config/gh, and her host's drvPath must not move for it.
    pkgs.gh
    pkgs.file
    pkgs.nvd
    pnpmZshCompletion
  ];

  # compinit caches its fpath scan in ~/.zcompdump-*, and decides the cache is
  # fresh by mtime -- but Nix pins every store mtime to 1970, so a newly added
  # completion (e.g. pnpmZshCompletion above) is invisible and Tab silently
  # keeps doing nothing. Same failure mode as the nvim luac cache in
  # modules/neovim.nix. Wipe it on every activation; the next shell rebuilds it.
  home.activation.clearZshCompdump = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run rm -f "${config.home.homeDirectory}"/.zcompdump*
  '';

  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];
}
