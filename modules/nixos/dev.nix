# The developer tooling seam. Imported by EVERY host through commonModules, but
# wholly inert unless the host sets `local.dev.enable`. hplaptop leaves it off:
# a non-technical user's machine with no nix-ld, ollama, opencode, nodejs, uv,
# jq, python3, and no sshd.
{
  config,
  lib,
  pkgs,
  unstablePkgs,
  user,
  ...
}:

let
  cfg = config.local.dev;
in
{
  options.local.dev.enable = lib.mkEnableOption "developer tooling (nix-ld, ollama, opencode, nodejs, uv, jq, python3, sshd)";

  config = lib.mkIf cfg.enable {
    # A real dynamic loader at /lib/ld-linux-*.so.* plus NIX_LD, so prebuilt
    # binaries fetched outside Nix can execute. Without it that path is stub-ld
    # and every such binary dies with a bare "No such file or directory" — which
    # is the real cause behind the hand-maintained LSP list and name-mapping table
    # in modules/home/neovim.nix (Mason downloads prebuilt binaries).
    programs.nix-ld.enable = true;

    # The SSH authorized key is dev-only because sshd itself is (see
    # services.openssh below). `lib.optionals` rather than a bare list: a dev host
    # whose user.nix entry has no `sshKey` gets sshd with an empty key list, while
    # a bare list fails evaluation with `error: attribute 'sshKey' missing`.
    users.users.${user.username}.openssh.authorizedKeys.keys = lib.optionals (user ? sshKey) [
      user.sshKey
    ];

    # On `nodejs`, `uv` and `python3` being GLOBAL, which looks like it violates
    # the per-project-devshell rule: they are AGENT RUNTIMES, not project
    # toolchains. The dev-workflow skills execute from ~/.agents/skills — outside
    # any project, so no devshell can supply their interpreters and launchers.
    # nodejs runs the skills' .cjs scripts (and brings npm/npx); `uvx` fetches its
    # own standalone Python builds, which run under nix-ld above; python3 is for
    # one-off scripting from sessions outside any project — `pip install` outside
    # a venv fails by design on NixOS, and project code belongs in
    # templates/python-devshell/.
    environment.systemPackages = with pkgs; [
      # From nixos-unstable: opencode is a fast-moving userland CLI whose bumps
      # land on unstable only, so 26.05 lags upstream (doc/workflow.md). The
      # second tree is forced only here and in hosts/geekom/default.nix, because
      # this list sits inside `mkIf cfg.enable`.
      unstablePkgs.opencode
      nodejs
      jq # ollama, opencode and the flake all speak JSON
      uv
      python3
    ];

    # Off on hplaptop (dev.enable = false): Elisa updates via `nrb`, no SSH needed.
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;

        # Explicit, though the default (`prohibit-password`) is already inert
        # here: root has no authorized key. Stating it removes the reliance on
        # that inference — a future root key added for some unrelated reason would
        # otherwise open root SSH, with a default nobody wrote down in the way.
        PermitRootLogin = "no";
      };
    };

    # Ollama. The ENABLE is shared, the PACKAGE is not: this CPU-only default is
    # all the aarch64 VM can use (it renders in software, no GPU to talk to),
    # while geekom overrides it to ollama-vulkan in its own host file, next to the
    # GPU that reasoning applies to.
    #
    # Deliberately NOT setting `services.ollama.acceleration`: it was REMOVED in
    # 26.05 and any config that sets it fails to evaluate — tutorials still show
    # it. The cfg.package swap above is the replacement. The `ollama` CLI arrives
    # with the module, so listing it in systemPackages would be redundant.
    services.ollama.enable = true;

    # Declarative secrets (sops-nix). Two boundaries must not be conflated:
    # TRUST (who can decrypt — recipient keys in .sops.yaml; hplaptop is not a
    # recipient, so the ciphertext is opaque to her) and DEV GATE (who declares
    # and mounts them — this block, so hplaptop never evaluates sops.secrets and
    # never pulls in the sops binary). Belt to .sops.yaml's braces: a secret
    # nobody declares is never shipped to a machine.
    #
    # defaultSopsFile as a store path (the repo file captured by the flake) is
    # what sops-nix's eval-time check needs: `validateSopsFiles` (default on)
    # throws when a declared sops file is missing or outside the store. It does
    # NOT check the ciphertext's keys — a `sops.secrets.<NAME>` typo evaluates
    # green and only fails at activation (doc/secrets.md). Ciphertext in the
    # store is inert — only the host's key opens it.
    sops.defaultSopsFile = ../../secrets/andrea/secrets.yaml;
    # Explicit for self-documentation though sops-nix already defaults to these:
    # a reader should not have to know upstream defaults to know how the machine
    # unlocks secrets. The personal age key is deliberately NOT listed — it lives
    # in ~/.config/sops/age/ only where a human edits secrets, not where they are
    # consumed.
    sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    sops.secrets.CONTEXT7_API_KEY = {
      # Owned by the dev user so the guarded shell export can `cat` it without
      # root; mode 0400 (sops default) keeps it single-reader.
      owner = user.username;
    };
    # Second consumer of the shell-export pattern: ~/code/typesafe-lab's `real`
    # provider reads TYPESAFE_API_KEY from the environment. Same owner/mode.
    sops.secrets.TYPESAFE_API_KEY = {
      owner = user.username;
    };
  };
}
