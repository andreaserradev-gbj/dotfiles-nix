# The docker seam. Imported by EVERY host through commonModules, but wholly
# inert unless the host sets `local.docker.enable`. The VM leaves it off: it is
# a cage+foot kiosk on a software renderer, not a machine anything is built on.
# `local.*` is this repo's own option namespace; nothing upstream owns it.
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

    # Published ports bypass the NixOS firewall, so a container binds on the LAN
    # unless the address says otherwise. `ip` covers the DEFAULT bridge only —
    # compose networks need an explicit `127.0.0.1:` in every `ports:` entry.
    virtualisation.docker.daemon.settings.ip = "127.0.0.1";

    # THE `docker` GROUP IS ROOT-EQUIVALENT: any member can run
    # `docker run -v /:/host --privileged` and own the filesystem, with no sudo
    # password in the path. Accepted because this user is already in `wheel`, so
    # the only thing removed is that prompt — re-decide if this box ever gains a
    # second user. `virtualisation.docker.rootless.enable` needs no group, but
    # cannot bind ports below 1024 without extra work.
    users.users.${user.username}.extraGroups = [ "docker" ];

    # Compose is not part of the daemon package.
    environment.systemPackages = [ pkgs.docker-compose ];

    # DELIBERATELY NOT SET: `enableOnBoot` (false still works via socket
    # activation, but `restart: always` containers stop coming back after a
    # reboot) and `autoPrune` — never add `--volumes` to it: that deletes every
    # volume not attached to a RUNNING container when the timer fires.
  };
}
