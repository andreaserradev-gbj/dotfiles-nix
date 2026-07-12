# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{
  config,
  lib,
  pkgs,
  user,
  ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;

  # aarch64 UTM VM: do NOT write boot entries into firmware NVRAM
  boot.loader.efi.canTouchEfiVariables = false;

  # Network identity
  networking.hostName = "nixos"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Rome";

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

  # Set-once: pin state-format defaults to the install release. Never bump casually.
  system.stateVersion = "26.05"; # Did you read the comment?

}
