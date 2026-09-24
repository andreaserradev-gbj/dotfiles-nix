# Personal identity, keyed by hostname — the ONE file to edit when forking this
# config or adding a host. `flake.nix` resolves the per-host attrset via
# `specialArgs = { user = users.${hostname}; ... }` for both NixOS and HM.
let
  # The flake every host updates ITSELF from (`nrb`, modules/home/maintenance.nix);
  # it lives here so a fork that edited only this file stops pulling upstream.
  # `bootstrap.sh` spells the URL out too — it runs before the clone exists.
  repo = "github:andreaserradev-gbj/dotfiles-nix";

  # flake.nix looks the attrset up as `users.${hostname}`, so both dev hosts
  # share one identity rather than duplicating it per machine.
  owner = rec {
    username = "andrea";
    fullName = "Andrea Serra";
    email = "andreaserradev-gbj@users.noreply.github.com";
    timeZone = "Europe/Rome";

    # No `sshKey` — a DELIBERATE absence, not an oversight: dev.nix treats the
    # field as optional, so nothing breaks without it. Consequence: geekom's sshd
    # has an empty authorized-keys list until a key is enrolled by adding
    # `sshKey = "<its public key>";` here, generated ON that machine.
    homeDirectory = "/home/${username}"; # rec: this interpolates username
    inherit repo; # `inherit` inside `rec` reads the enclosing let, not the set
  };
in
{
  nixos = owner;
  geekom = owner;

  # Non-technical user on the hplaptop host. No `sshKey` (sshd is off there —
  # gated behind `local.dev.enable`) and no `email` (its only consumer, git.nix,
  # is dev-gated too). `keyboardLayout` and `locale` are OPTIONAL: present, they
  # drive the console keymap, XKB/GDM layout, GNOME input sources and the system
  # locale; absent means the platform default, as on the dev hosts.
  hplaptop = rec {
    username = "elisa";
    fullName = "Elisa Davi";
    timeZone = "Europe/Rome";
    keyboardLayout = "it";
    locale = "it_IT.UTF-8";
    homeDirectory = "/home/${username}";
    inherit repo;
  };
}
