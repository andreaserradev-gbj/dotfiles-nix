# Shared NixOS configuration — imported by every host.
# Anything host-specific (hostName, stateVersion, hardware, display stack)
# belongs in hosts/<host>/ instead, NOT here.
{
  pkgs,
  user,
  ...
}:

{
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;

  # Cap the boot menu at the 10 most recent generations. Without this it grows
  # unbounded; cleared generations also linger in /boot/loader/entries until a
  # `nixos-rebuild boot`/`switch` reconciles the loader entries.
  boot.loader.systemd-boot.configurationLimit = 10;

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # Set your time zone (lifted into user.nix — the one file a forker edits).
  time.timeZone = user.timeZone;

  programs.zsh.enable = true;

  # Account informations
  users.users.${user.username} = {
    isNormalUser = true;
    description = user.fullName;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    initialPassword = "nixos"; # throwaway
    openssh.authorizedKeys.keys = [ user.sshKey ];
  };

  # List packages installed in system profile.
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
  ];

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Modern `nix` CLI + flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
