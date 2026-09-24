# Shared NixOS configuration — imported by every host. Host-specific settings
# (hostName, stateVersion, hardware, display stack) belong in hosts/<host>/.
{
  pkgs,
  lib,
  user,
  ...
}:

{
  boot.loader.systemd-boot.enable = true;

  # Without this the boot menu and /boot/loader/entries grow unbounded.
  boot.loader.systemd-boot.configurationLimit = 10;

  # The default (`true`) lets anyone at the boot menu press `e` and boot with
  # `init=/bin/sh` — a root shell with no login. Worst on hplaptop, no LUKS.
  boot.loader.systemd-boot.editor = false;

  networking.networkmanager.enable = true;

  # Wi-Fi power saving parks the radio between beacons, so packets for an idle
  # station wait for the next DTIM — battery life this mains-powered box does not
  # have. Measured ~80 ms inbound round trips vs ~23 ms outbound to the same
  # gateway: the asymmetry that makes SSH feel laggy while throughput looks fine.
  # Bare assignment (priority 100, `defaultOverridePriority`); hplaptop's
  # `lib.mkForce` (priority 50) is lower, so it wins there.
  networking.networkmanager.wifi.powersave = false;

  time.timeZone = user.timeZone;

  # TTY layouts only; the graphical layout is set from the same field in
  # desktop.nix, so the two cannot disagree. Optional: no field → kernel "us".
  console.keyMap = user.keyboardLayout or "us";

  # Optional (hosts without `locale` keep the nixpkgs default); the config below
  # must stay byte-identical on those hosts — same rule as modules/home/desktop.nix.
  i18n.defaultLocale = user.locale or "en_US.UTF-8";
  i18n.supportedLocales = lib.mkIf (user ? locale) [ "all" ];

  programs.zsh.enable = true;

  users.users.${user.username} = {
    isNormalUser = true;
    description = user.fullName;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    initialPassword = "nixos"; # throwaway
  };

  # Named predicate rather than a blanket `allowUnfree`: anything ELSE unfree
  # that wanders in as a dependency still fails eval. This list is the complete
  # set of accepted packages.
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "steam"
      "steam-unwrapped"
    ];

  # `git` here is the system's VCS (for `nixos-rebuild`); the user's dev git
  # config is in modules/home/git.nix and IS dev-gated.
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # No substituter is declared, deliberately: the key of the only cache a tool
  # flake advertises would be trusted for EVERY store path on every host, for a
  # cache nothing here consumes. Rationale and the trust scope: doc/omp.md.
  # cache.nixos.org remains the default.
}
