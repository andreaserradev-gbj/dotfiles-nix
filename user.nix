# Personal identity, keyed by hostname — the ONE file to edit when forking this
# config or adding a host. `flake.nix` resolves the per-host attrset via
# `specialArgs = { user = users.${hostname}; ... }` for both NixOS and HM.
let
  # The flake hplaptop updates itself from (her `nrb`, modules/home/maintenance.nix
  # — the only consumer); it lives here so a fork that edited only this file stops
  # pulling upstream. `bootstrap.sh` spells the URL out too — it runs before the
  # clone exists.
  repo = "github:andreaserradev-gbj/dotfiles-nix";

  # flake.nix looks the attrset up as `users.${hostname}`, so both dev hosts
  # share one identity rather than duplicating it per machine.
  owner = rec {
    username = "andrea";
    fullName = "Andrea Serra";
    email = "andreaserradev-gbj@users.noreply.github.com";
    timeZone = "Europe/Rome";

    # `sshKey` is OPTIONAL — dev.nix treats it as optional, so a host whose
    # user.nix entry omits it still builds (sshd with an empty key list).
    # The value is a LIST, and each entry MUST carry its own `from=` scope: an
    # unscoped key is valid from every address sshd is reachable on, which is
    # exactly what the scope is meant to prevent. `/22` rather than a single
    # address because DHCP hands out a different lease per interface and per
    # renewal; the scope is the network, and the tailnet CGNAT range is inert
    # until Phase 4.
    sshKey = [
      ''from="100.64.0.0/10,192.168.68.0/22" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHvurFqssVcB/zISvASNgcqzTfeWIw44Hj7mSs0wFvXI phone''
    ];

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
