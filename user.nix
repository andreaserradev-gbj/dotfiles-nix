# Personal identity, keyed by hostname — the ONE file to edit when forking
# this config or adding a host. `flake.nix` resolves the per-host attrset via
# `specialArgs = { user = users.${hostname}; ... }` and threads it through
# both NixOS and Home Manager.
let
  # The flake every host updates ITSELF from: `modules/home/maintenance.nix`
  # builds the `nrb` alias out of this. It lives here rather than in the
  # module because a fork that edited only `user.nix` would otherwise keep
  # pulling the upstream repo — on the unattended laptop, silently and
  # forever. `bootstrap.sh` still spells the URL out; that one runs before
  # the clone exists, so it cannot read this file and is the single
  # unavoidable literal.
  repo = "github:andreaserradev-gbj/dotfiles-nix";

  # Both dev hosts are the same person. The file is keyed by HOSTNAME only
  # because flake.nix looks the attrset up as `users.${hostname}`, so the
  # person is named once here and assigned to hosts below — otherwise an
  # email change is one edit per machine and each new host copies seven more
  # lines of the same identity.
  owner = rec {
    username = "andrea";
    fullName = "Andrea Serra";
    email = "andreaserradev-gbj@users.noreply.github.com";
    timeZone = "Europe/Rome";
    sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINROirqL4mIWQh/x4+ka3dBvO/9mp0MTaaT3PglqAfnU andrea.serra.dev@gmail.com";
    homeDirectory = "/home/${username}"; # rec lets this reference username
    inherit repo; # `inherit` inside `rec` reads the enclosing let, not the set
  };
in
{
  nixos = owner;
  geekom = owner;

  # Non-technical user on the hplaptop host.
  #
  # No `sshKey`: sshd is off on hplaptop (gated behind `local.dev.enable`, which
  # is false here), so nothing consumes it. No `email`: the only consumer was
  # `modules/home/git.nix` (dev-gated, not imported on hplaptop), and Elisa's
  # email is configured directly in Brave with her Google account — no native
  # mail client. Adding a future non-dev HM module that consumes either field
  # on hplaptop would need both added back here.
  #
  # `keyboardLayout` is OPTIONAL — the other hosts omit it and keep the
  # platform default ("us"). When present it drives the console keymap, the
  # XKB/GDM layout and GNOME's input sources (see common.nix and desktop.nix).
  #
  # `locale` is OPTIONAL the same way. When present it sets the whole system
  # locale (messages, formats, measurements — see common.nix). Absent = the
  # nixpkgs default ("en_US.UTF-8"), byte-identical behavior for existing hosts.
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
