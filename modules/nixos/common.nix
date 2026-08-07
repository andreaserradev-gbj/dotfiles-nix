# Shared NixOS configuration — imported by every host.
# Anything host-specific (hostName, stateVersion, hardware, display stack)
# belongs in hosts/<host>/ instead, NOT here.
{
  pkgs,
  lib,
  user,
  inputs,
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

  # A real dynamic loader at /lib/ld-linux-*.so.*, plus NIX_LD, so prebuilt
  # binaries fetched outside Nix can actually execute. Without this that path is
  # stub-ld and every such binary dies with a bare "No such file or directory".
  # That is the real cause behind the hand-maintained LSP server list and its
  # name-mapping table in modules/home/neovim.nix: Mason downloads prebuilt
  # binaries, so it could never have worked here.
  programs.nix-ld.enable = true;

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

  # Upstream claude-code flake, which tracks releases ahead of nixpkgs. This is
  # what makes `claude-code` below resolve to the flake build, not nixpkgs'.
  nixpkgs.overlays = [ inputs.claude-code.overlays.default ];

  # Named predicate rather than a blanket `allowUnfree`: anything ELSE unfree
  # that wanders in as a dependency still fails eval instead of being waved
  # through silently. The list is the complete set of unfree packages accepted.
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
    ];

  # List packages installed in system profile.
  #
  # On `nodejs` being global, which LOOKS like it violates this repo's
  # per-project-devshell rule: it is an AGENT RUNTIME, not a project toolchain.
  # The dev-workflow skills execute from ~/.agents/skills and ~/.claude/plugins
  # — outside any project, so no devshell can ever supply their interpreter.
  # Same reasoning that puts the harnesses themselves here. Project toolchains
  # still belong in per-project devshells; do not use this line as precedent.
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
    claude-code # unfree — see allowUnfreePredicate above
    opencode # second agent harness; free licence, so no predicate entry needed
    nodejs # runtime for the skills' .cjs scripts (also provides npm/npx)
  ];

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Ollama. Used as a CLOUD client here — no local model weights, no GPU
  # involved — so this is identical on the aarch64 VM and on geekom.
  #
  # Deliberately NOT setting `services.ollama.acceleration`: it was REMOVED in
  # 26.05 and any config that sets it fails to evaluate. Tutorials still show
  # it. If local GPU inference is ever wanted, the replacement is
  # `services.ollama.package = pkgs.ollama-rocm` (or -vulkan/-cuda/-cpu).
  #
  # The `ollama` CLI arrives automatically — the module puts cfg.package into
  # environment.systemPackages, so listing it above would be redundant.
  services.ollama.enable = true;

  # Modern `nix` CLI + flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
