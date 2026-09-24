# The loopback-rebuild seam: with `local.loopbackRebuild.enable`,
# modules/home/shell.nix gives nrs/nrt `--target-host <user>@localhost`, so the
# activation runs inside sshd's session scope instead of the graphical session
# that launched it — doc/workflow.md's "never run `nrs` from the graphical
# console" hazard, discharged without a second machine. Inert without `enable`.
#
# `authorizedKey`/`hostKey` are per-host literals BY DESIGN: they must not be read
# off the running system (same reason user.nix's `repo` is a literal) — a config
# that derives its own state from the machine it describes cannot be rebuilt from
# a clean checkout. Both values are public; the matching PRIVATE key lives at
# ~/.ssh/id_ed25519 on the host and is deliberately unmanaged (a private key in a
# store path would be world-readable). Generate it WITHOUT a passphrase — an
# unattended rebuild cannot type one.
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

    # The host's OWN user key (`ssh-keygen -lf ~/.ssh/id_ed25519.pub` identifies
    # it), merged with the keys dev.nix already manages. Loopback-only below: the
    # key is passphrase-less and sits on the machine.
    authorizedKey = lib.mkOption {
      type = lib.types.str;
      description = "This host's own SSH public key, authorized for loopback only (from=\"127.0.0.1,::1\") — the machine SSHing into itself, not a way in from anywhere else.";
    };

    # Pinned via knownHosts so the manual `ssh-keyscan` step is gone; hostNames
    # covers the three ways `localhost` resolves, so a resolver change cannot look
    # like a MITM.
    hostKey = lib.mkOption {
      type = lib.types.str;
      description = "This host's own sshd public key (the .pub of /etc/ssh/ssh_host_ed25519_key), pinned as the known host key for localhost.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${user.username}.openssh.authorizedKeys.keys = [
      "from=\"127.0.0.1,::1\" ${cfg.authorizedKey}"
    ];

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
