# The docker seam. Imported by EVERY host through commonModules, but wholly
# inert unless the host sets `local.docker.enable`. The VM leaves it off: it is
# a cage+foot kiosk on a software renderer, not a machine anything is built on.
#
# `local.*` is this repo's own option namespace — nothing upstream owns it, so
# there is no collision risk as more seams (hyprland, …) get added.
{
  config,
  lib,
  pkgs,
  user,
  ...
}:

let
  cfg = config.local.docker;
in
{
  options.local.docker.enable = lib.mkEnableOption "the Docker stack (dockerd, compose)";

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    # THE `docker` GROUP IS ROOT-EQUIVALENT. Any member can run
    # `docker run -v /:/host --privileged` and own the filesystem, and no sudo
    # password appears anywhere in that path.
    #
    # Taken deliberately, and the reason is narrower than the warning sounds:
    # this user is already in `wheel`, so the group grants no capability that
    # was not already reachable. What it removes is the password prompt in
    # front of it. That is a genuine reduction, and it is not the same thing as
    # no change at all — it is worth re-deciding if this box ever gains a
    # second user, or gets exposed to anything but the LAN.
    #
    # The alternative is `virtualisation.docker.rootless.enable`, which needs
    # no group. Not used because it cannot bind ports below 1024 without extra
    # work, and tooling that assumes /var/run/docker.sock has to be talked out
    # of it one program at a time.
    users.users.${user.username}.extraGroups = [ "docker" ];

    # Compose is not part of the daemon package. This derivation ships both
    # `bin/docker-compose` and `libexec/docker/cli-plugins/docker-compose`, so
    # the hyphenated form is certain and the `docker compose` subcommand form
    # depends on the CLI finding the plugin directory.
    environment.systemPackages = [ pkgs.docker-compose ];

    # DELIBERATELY NOT SET:
    #
    # `enableOnBoot` — left at its default of true. Setting it false would
    # still give a working docker through socket activation, but containers
    # marked `restart: always` would stop coming back after a reboot. That is
    # a behaviour to choose on purpose, not to acquire while tidying.
    #
    # `autoPrune` — off. If it is ever switched on, do NOT put `--volumes` in
    # its flags. That deletes every volume not attached to a RUNNING container,
    # so stopping a dev database and letting the timer fire destroys its data.
  };
}
