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
    { nixpkgs, home-manager, ... }:
    let
      user = import ./user.nix;

      # Shared by every host. Host-specific configuration — hostName,
      # stateVersion, hardware, display stack — lives in hosts/<host>/.
      # Deliberately a plain list, not a mkSystem helper: at two hosts with no
      # builder divergence, the helper would be indirection for ~10 saved lines.
      commonModules = [
        ./modules/nixos/common.nix
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
        specialArgs = { inherit user; };
        modules = commonModules ++ [
          ./hosts/vm
        ];
      };

      templates.devshell = {
        path = ./templates/devshell;
        description = "Per-project dev shell: flake + direnv";
      };
    };
}
