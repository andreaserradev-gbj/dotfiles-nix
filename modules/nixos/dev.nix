# The developer tooling seam. Imported by EVERY host through commonModules,
# but wholly inert unless the host sets `local.dev.enable`. hplaptop leaves it
# off: it is a non-technical user's machine with no nix-ld, ollama, opencode,
# nodejs, uv, jq, python3, and no sshd.
#
# `local.*` is this repo's own option namespace — nothing upstream owns it, so
# there is no collision risk as more seams (desktop, gaming, docker, dev, …)
# get added.
{
  config,
  lib,
  pkgs,
  user,
  ...
}:

let
  cfg = config.local.dev;
in
{
  options.local.dev.enable = lib.mkEnableOption "developer tooling (nix-ld, ollama, opencode, nodejs, uv, jq, python3, sshd)";

  config = lib.mkIf cfg.enable {
    # A real dynamic loader at /lib/ld-linux-*.so.*, plus NIX_LD, so prebuilt
    # binaries fetched outside Nix can actually execute. Without this that path is
    # stub-ld and every such binary dies with a bare "No such file or directory".
    # That is the real cause behind the hand-maintained LSP server list and its
    # name-mapping table in modules/home/neovim.nix: Mason downloads prebuilt
    # binaries, so it could never have worked here.
    programs.nix-ld.enable = true;

    # Account informations — the SSH authorized key is dev-only because sshd
    # itself is gated behind this seam (see services.openssh below). A host with
    # `local.dev.enable = false` (hplaptop) gets no sshd and no key.
    users.users.${user.username}.openssh.authorizedKeys.keys = [ user.sshKey ];

    # On `nodejs`, `uv` and `python3` being global, which LOOKS like it violates
    # this repo's per-project-devshell rule: they are AGENT RUNTIMES, not
    # project toolchains. The dev-workflow skills execute from
    # ~/.agents/skills — outside any project, so no devshell can ever supply
    # their interpreters and launchers.
    #
    # nodejs: runtime for the skills' .cjs scripts (also provides npm/npx).
    # uv: fast Python package installer/resolver (Rust) and a LAUNCHER —
    # uvx (uv's nix-run equivalent) fetches its own standalone Python builds
    # (python-build-standalone) that run under programs.nix-ld above.
    # python3: added 2026-08-29 after repeated one-off scripting needs
    # (JSON/YAML validation, quick computations) from sessions outside any
    # project — previously worked around with ad-hoc `nix shell nixpkgs#yq`.
    # Same agent-runtime reasoning as nodejs. It is NOT a project toolchain:
    # `pip install` outside a venv fails by design on NixOS, and project code
    # still belongs in the python-devshell template (see below).
    environment.systemPackages = with pkgs; [
      opencode # agent harness; free licence, so no predicate entry needed
      nodejs # runtime for the skills' .cjs scripts (also provides npm/npx)
      jq # ollama, opencode and the flake all speak JSON
      uv
      # Cloned repos that need a flake-pinned Python use the python-devshell
      # template instead — see templates/python-devshell/.
      python3 # CPython 3.13 (26.05 default); agent one-off scripting, see above
    ];

    # Enable the OpenSSH daemon. Off on hplaptop (dev.enable = false) — Elisa
    # updates via `nrb` (fetches from GitHub), no SSH access needed on her box.
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };

    # Ollama. The ENABLE is shared; the PACKAGE is not. This default build is
    # CPU-only, which is all the aarch64 VM can use — it renders in software and
    # has no GPU to talk to. geekom overrides cfg.package to ollama-vulkan in its
    # own host file; the reasoning for Vulkan-over-ROCm lives there, next to the
    # GPU it applies to.
    #
    # Deliberately NOT setting `services.ollama.acceleration`: it was REMOVED in
    # 26.05 and any config that sets it fails to evaluate. Tutorials still show
    # it. The replacement is the cfg.package swap described above.
    #
    # The `ollama` CLI arrives automatically — the module puts cfg.package into
    # environment.systemPackages, so listing it above would be redundant.
    services.ollama.enable = true;

    # Declarative secrets (sops-nix). Two boundaries must not be conflated:
    #
    # 1. TRUST BOUNDARY: who can decrypt. Set in .sops.yaml by recipient
    #    keys — hplaptop's host key is not a recipient, so even the
    #    ciphertext copied there is opaque to it. That layer costs nothing
    #    here; it lives in .sops.yaml.
    # 2. DEV-GATE BOUNDARY: who declares and mounts secrets. This whole
    #    block is inside `mkIf cfg.enable`, so hplaptop never even
    #    evaluations sops.secrets — nothing is added to its activation
    #    script, /run/secrets stays empty, no sops binary is pulled in.
    #    Belt to .sops.yaml's braces: a secret nobody declares is never
    #    shipped to the machine at all.
    #
    # defaultSopsFile is a STORE PATH (repo file captured by the flake),
    # not an absolute string: that is what makes sops-nix validate at EVAL
    # time that every declared secret key exists in the ciphertext — a
    # missing/renamed key fails check-hosts.sh instead of failing silently
    # at activation on a rebuild machine weeks later. Ciphertext in the
    # store is inert; only the host's own SSH key can open it.
    sops.defaultSopsFile = ../../secrets/andrea/secrets.yaml;
    # Explicit for self-documentation, though sops-nix already defaults to
    # the ed25519 host keys: a reader should not have to know upstream
    # defaults to know how their machine unlocks secrets. (The personal age
    # key is intentionally NOT listed: it lives in ~/.config/sops/age/ only
    # on machines where a human edits secrets, not where they are consumed.)
    sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    sops.secrets.CONTEXT7_API_KEY = {
      # Owned by the dev user so the guarded shell export can `cat` it
      # without root; mode 0400 (sops default) keeps it single-reader.
      owner = user.username;
    };
  };
}
