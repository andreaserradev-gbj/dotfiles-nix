# Shared NixOS configuration — imported by every host.
# Anything host-specific (hostName, stateVersion, hardware, display stack)
# belongs in hosts/<host>/ instead, NOT here.
{
  pkgs,
  lib,
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

  # Wi-Fi power saving parks the radio between beacons, so packets arriving for an
  # idle station wait for the next DTIM instead of being delivered at once. On a
  # mains-powered mini PC that trades interactive latency for battery life that
  # does not exist. It measured as ~80ms round trips inbound to this host while
  # outbound traffic to the same gateway was ~23ms — exactly the asymmetry that
  # makes an SSH session feel laggy while throughput still looks fine.
  # Bare assignment (priority 100, `defaultOverridePriority`); a laptop host
  # (hplaptop) overrides to `true` with `lib.mkForce` (priority 50) — LOWER
  # priority wins. No `mkDefault` here (priority 1000) because it would tie
  # with nixpkgs' own `mkDefault` on the same option and cause an eval conflict.
  networking.networkmanager.wifi.powersave = false;

  # Set your time zone (lifted into user.nix — the one file a forker edits).
  time.timeZone = user.timeZone;

  # Console (TTY) keyboard layout, lifted into user.nix like timeZone. The
  # field is optional: hosts without it keep the kernel default ("us"). This
  # covers the TTYs only; the graphical layout is set in desktop.nix, and the
  # two are set from the same field so they can never disagree.
  console.keyMap = user.keyboardLayout or "us";

  # System locale — messages, number/date formats, measurement units, and the
  # default language of every app that follows the session locale (GNOME,
  # LibreOffice, Brave, ...). Lifted into user.nix like timeZone. Optional:
  # hosts without it keep the nixpkgs default AND the default `supportedLocales`
  # (the config below must stay byte-identical on hosts that don't opt in —
  # same rule that keeps the keyboard dconf key off geekom).
  i18n.defaultLocale = user.locale or "en_US.UTF-8";
  i18n.supportedLocales = lib.mkIf (user ? locale) [ "all" ];

  programs.zsh.enable = true;

  # Account informations
  # `shell = pkgs.zsh` wins over nixpkgs' `mkDefault "/bin/bash"` for
  # isNormalUser by priority: a bare assignment is 100 and `mkDefault` is 1000,
  # and LOWER wins. A host that wants a different shell (hplaptop → bash)
  # overrides with `lib.mkForce` (priority 50), lower still.
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
  # that wanders in as a dependency still fails eval instead of being waved
  # through silently. The list is the complete set of unfree packages accepted.
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "steam"
      "steam-unwrapped"
    ];

  # List packages installed in system profile.
  #
  # `vim`, `wget`, `git` are baseline system tools, NOT dev tooling — `git` here
  # is the VCS the system uses (for `nixos-rebuild`), not the user's dev git
  # config which lives in modules/home/git.nix (and IS dev-gated).
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
  ];

  # Modern `nix` CLI + flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
