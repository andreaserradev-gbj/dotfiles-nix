# Personal identity, keyed by hostname — the ONE file to edit when forking
# this config or adding a host. `flake.nix` resolves the per-host attrset via
# `specialArgs = { user = users.${hostname}; ... }` and threads it through
# both NixOS and Home Manager.
{
  nixos = rec {
    username = "andrea";
    fullName = "Andrea Serra";
    email = "andreaserradev-gbj@users.noreply.github.com";
    timeZone = "Europe/Rome";
    sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINROirqL4mIWQh/x4+ka3dBvO/9mp0MTaaT3PglqAfnU andrea.serra.dev@gmail.com";
    homeDirectory = "/home/${username}"; # rec lets this reference username
  };

  geekom = rec {
    username = "andrea";
    fullName = "Andrea Serra";
    email = "andreaserradev-gbj@users.noreply.github.com";
    timeZone = "Europe/Rome";
    sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINROirqL4mIWQh/x4+ka3dBvO/9mp0MTaaT3PglqAfnU andrea.serra.dev@gmail.com";
    homeDirectory = "/home/${username}";
  };

  # Non-technical user on the hplaptop host.
  #
  # No `sshKey`: sshd is off on hplaptop (gated behind `local.dev.enable`, which
  # is false here), so nothing consumes it. No `email`: the only consumer was
  # `modules/home/git.nix` (dev-gated, not imported on hplaptop), and Elisa's
  # email is configured directly in Brave with her Google account — no native
  # mail client. Adding a future non-dev HM module that consumes either field
  # on hplaptop would need both added back here.
  hplaptop = rec {
    username = "elisa";
    fullName = "Elisa Davi";
    timeZone = "Europe/Rome";
    homeDirectory = "/home/${username}";
  };
}
