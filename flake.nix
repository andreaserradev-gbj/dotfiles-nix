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
      user = import ./user.nix;

      # Shared by every host. Host-specific configuration — hostName,
      # stateVersion, hardware, display stack — lives in hosts/<host>/.
      # Deliberately a plain list, not a mkSystem helper: at two hosts with no
      # builder divergence, the helper would be indirection for ~10 saved lines.
      #
      # desktop.nix is listed here rather than under hosts/geekom because it
      # DEFINES the `local.desktop` option as well as consuming it: every host
      # must be able to see the option in order to leave it off.
      commonModules = [
        ./modules/nixos/common.nix
        ./modules/nixos/desktop.nix
        ./modules/nixos/gaming.nix
        ./modules/nixos/docker.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = { inherit user; };
          home-manager.users.${user.username} = import ./home.nix;
        }
      ];
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit user inputs; };
        modules = commonModules ++ [
          ./hosts/vm
        ];
      };

      nixosConfigurations.geekom = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit user inputs; };
        modules = commonModules ++ [
          ./hosts/geekom
        ];
      };

      templates.devshell = {
        path = ./templates/devshell;
        description = "Per-project dev shell: flake + direnv";
      };
    };
}
