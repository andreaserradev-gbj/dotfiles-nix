# Personal identity — the ONE file to edit when forking this config.
# Threaded everywhere via specialArgs (NixOS) + extraSpecialArgs (Home Manager).
rec {
  username = "andrea";
  fullName = "Andrea Serra";
  email = "andreaserradev-gbj@users.noreply.github.com";
  timeZone = "Europe/Rome";
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINROirqL4mIWQh/x4+ka3dBvO/9mp0MTaaT3PglqAfnU andrea.serra.dev@gmail.com";
  homeDirectory = "/home/${username}"; # rec lets this reference username
}
