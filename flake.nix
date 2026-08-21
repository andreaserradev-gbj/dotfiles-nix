{
  description = "Personal NixOs + Home Manager configuration — multi-host";

  inputs = {

    nixpkgs.url = "github:NixOs/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ nixpkgs, home-manager, ... }:
    let
      users = import ./user.nix;

      # Shared by every host. Host-specific configuration — hostName,
      # stateVersion, hardware, display stack — lives in hosts/<host>/.
      # Deliberately a plain list, not a mkSystem helper: at two hosts with no
      # builder divergence, the helper would be indirection for ~10 saved lines.
      #
      # desktop.nix is listed here rather than under hosts/geekom because it
      # DEFINES the `local.desktop` option as well as consuming it: every host
      # must be able to see the option in order to leave it off.
      #
      # `user` is resolved per-host below (users.${hostname}) so each host sees
      # its own identity attrset via specialArgs. home-manager.extraSpecialArgs
      # threads the same per-host `user` through to HM.
      commonModules = [
        ./modules/nixos/common.nix
        ./modules/nixos/desktop.nix
        ./modules/nixos/gaming.nix
        ./modules/nixos/docker.nix
        ./modules/nixos/dev.nix
        home-manager.nixosModules.home-manager
        (
          { user, ... }:
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = { inherit user; };
            home-manager.users.${user.username} = import ./home.nix;
          }
        )
      ];
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {
          user = users.nixos;
          inherit inputs;
        };
        modules = commonModules ++ [
          ./hosts/vm
        ];
      };

      nixosConfigurations.geekom = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          user = users.geekom;
          inherit inputs;
        };
        modules = commonModules ++ [
          ./hosts/geekom
        ];
      };

      templates.devshell = {
        path = ./templates/devshell;
        description = "Per-project dev shell: flake + direnv";
      };

      templates.python-devshell = {
        path = ./templates/python-devshell;
        description = "Per-project Python dev shell: uv + python3 (pinned via flake.lock)";
      };

      # `nix fmt` runs this against the flake root. nixfmt in nixpkgs 26.05 IS
      # the RFC-style official formatter (the old `nixfmt-rfc-style` alias was
      # removed); same package that neovim.nix installs for conform.nvim, so
      # `nix fmt` and conform agree by construction.
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;
      formatter.aarch64-linux = nixpkgs.legacyPackages.aarch64-linux.nixfmt;

      # Minimal shell for hacking on this repo. The only tool that is NOT
      # already on the system profile (via modules/home/neovim.nix) is deadnix;
      # nixfmt, statix and nil are redundant here and listed only so a fresh
      # clone has a self-contained `nix develop` / direnv that does not depend
      # on having built and applied a host first. The pre-commit hook that
      # .envrc installs runs `nixfmt` from this shell, so the hook works on any
      # clone without relying on a previously-built system.
      devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShellNoCC {
        packages = with nixpkgs.legacyPackages.x86_64-linux; [
          nixfmt
          statix
          nil
          deadnix
        ];
      };
      devShells.aarch64-linux.default = nixpkgs.legacyPackages.aarch64-linux.mkShellNoCC {
        packages = with nixpkgs.legacyPackages.aarch64-linux; [
          nixfmt
          statix
          nil
          deadnix
        ];
      };
    };
}
