{ ... }:
{
  # opencode ships a self-updater that offers to replace a Nix-managed binary.
  # Accepting would leave the config declaring 1.15.10 while the machine ran
  # something else — drift the drvPath gate cannot see, because it happens
  # outside the store. Same hazard btop.nix guards against with
  # `save_config_on_exit = false`: a tool that rewrites what Nix declares turns
  # the config into a lie.
  #
  # claude-code needs no equivalent — nixpkgs and the sadjow flake both wrap it
  # with DISABLE_AUTOUPDATER=1. opencode has no such wrapper, so the off switch
  # has to come from config. Version freshness comes from `nix flake update`.
  #
  # The package itself lives in environment.systemPackages next to claude-code
  # (harnesses are machine-level); this module owns only the per-user config.
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    autoupdate = false;
  };
}
