# The loopback-rebuild seam. A host that sets `local.loopbackRebuild.enable`
# can run its OWN rebuild through SSH to itself (`nrs`/`nrt` in
# modules/home/shell.nix gain `--target-host <user>@localhost`), so the
# activation runs inside sshd's session scope instead of the graphical
# session that launched it — doc/workflow.md's "never run `nrs` from the
# machine's own graphical console" hazard, discharged without needing a
# second machine. Phase 1 of a switch can restart the display stack; sshd
# lives outside it, so the activation survives.
#
# Inert unless a host flips it on: the VM's aliases stay plain (it is usually
# rebuilt over SSH from outside anyway) and hplaptop never sees the aliases
# at all (shell.nix is dev-gated, and this whole file is inert without
# `enable`).
#
# The two keys are per-host literals BY DESIGN — this file does not and must
# not try to read them off the running system, for the same reason
# user.nix's `repo` is a literal: a config that derives its own state from
# the machine it is describing cannot be rebuilt from a clean checkout.
# The values are public (a public key is public); the corresponding PRIVATE
# key must already exist at ~/.ssh/id_ed25519 on the host itself. That file
# is deliberately NOT managed by the flake: HM programs.ssh has no
# key-generation option, and dropping a private key into a store path would
# make it world-readable. Forkers: `ssh-keygen -t ed25519 -N "" -f
# ~/.ssh/id_ed25519` once, then paste the .pub here.
#
# `user` is threaded via extraSpecialArgs from flake.nix (same as dev.nix).
{
  config,
  lib,
  user,
  ...
}:

let
  cfg = config.local.loopbackRebuild;
in
{
  options.local.loopbackRebuild = {
    enable = lib.mkEnableOption "loopback rebuilds: this host rebuilds itself over SSH to localhost, keeping activation outside the display stack (shell.nix wires nrs/nrt through --target-host)";

    # The host's OWN user key (e.g. `ssh-keygen -lf ~/.ssh/id_ed25519.pub`
    # identifies it). Appended to the authorized keys that dev.nix already
    # manages — a plain attrset list merge, no conflict — so the loopback
    # connection authenticates with the key that lives on the machine
    # itself, never with the Mac's key (whose private half must not be
    # copied anywhere).
    authorizedKey = lib.mkOption {
      type = lib.types.str;
      description = "This host's own SSH public key, authorized so the machine can SSH into itself.";
    };

    # Pinned via programs.ssh.knownHosts so the manual `ssh-keyscan` step is
    # gone: a fresh checkout + one rebuild pins localhost's host key before
    # the first loopback nrs ever runs. hostNames covers the three ways
    # `localhost` can resolve (it, 127.0.0.1, ::1) so a resolver change
    # cannot trigger a MITM warning — sshd binds both address families.
    hostKey = lib.mkOption {
      type = lib.types.str;
      description = "This host's own sshd public key (the .pub of /etc/ssh/ssh_host_ed25519_key), pinned as the known host key for localhost.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${user.username}.openssh.authorizedKeys.keys = [ cfg.authorizedKey ];

    programs.ssh.knownHosts."localhost" = {
      hostNames = [
        "localhost"
        "127.0.0.1"
        "::1"
      ];
      publicKey = cfg.hostKey;
    };
  };
}
