# The feature registry — the single place that knows where each feature lives.
#
# A plain attrset of PATHS, read as data. Not a module system: no
# lib.evalModules, no deferredModule, no apply shim, no new flake input, no
# new lock node. The shape is load-bearing (doc/dendritic-pattern.md):
#
#   A registry entry must be a PATH. A path adds no level to the import
#   graph, so the module system's genericClosure traversal — and every
#   drvPath derived from it — is unchanged. A module, a deferredModule or a
#   wrapper adds one level, and that extra level reorders the list-valued
#   contributions (environment.systemPackages), which changes system.path,
#   etc, dbus-1 and the toplevel derivation. Measured: a registry of paths
#   leaves all three hosts and all three Home Manager generations
#   byte-identical; every other shape moves at least one host.
#
# Two classes, one name space each. A feature may appear under both: `desktop`
# has a NixOS half and a Home Manager half, and they stay in separate files —
# merging them moves drvPaths, so the halves are registered separately.
#
# A feature name is not an option. The registry says where a feature lives;
# the import lists say which features a host gets. A seam module must stay in
# commonModules even when only one host enables it, because a host that cannot
# see an option cannot set it to false.
#
# A list-valued entry must be spliced FLAT with `++` where it is used, never
# nested inside an import list — a nested list is a hard evaluation error
# ("Module imports can't be nested lists"), not a quiet move.
{
  nixos = {
    common = ../modules/nixos/common.nix;
    desktop = ../modules/nixos/desktop.nix;
    gaming = ../modules/nixos/gaming.nix;
    docker = ../modules/nixos/docker.nix;
    dev = ../modules/nixos/dev.nix;
    loopbackRebuild = ../modules/nixos/loopback-rebuild.nix;
  };

  home = {
    desktop = [
      ../modules/home/gtk.nix
      ../modules/home/desktop.nix
    ];
    niri = [
      ../modules/home/niri.nix
      ../modules/home/mime.nix
    ];
  };
}
