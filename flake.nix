{
  description = "Personal NixOs + Home Manager configuration — multi-host";

  inputs = {

    nixpkgs.url = "github:NixOs/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative secret management (sops-nix). Follows our nixpkgs so the
    # module pins to exactly the sops/age versions the system would build
    # anyway — no second nixpkgs tree in the lockfile.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      sops-nix,
      ...
    }:
    let
      users = import ./user.nix;

      # The systems that get developer-facing outputs (`formatter`, `devShells`).
      # NOT the systems that get hosts: `nixosConfigurations` stay written out
      # one by one below, because each names a different host module and a
      # different `user`, so there is nothing to fold.
      #
      # aarch64-darwin is here because the Mac is where this repo is actually
      # edited. Without it `nix develop` fails, which makes `use flake` in
      # .envrc fail, which leaves `nixfmt` off PATH, which makes the
      # scripts/pre-commit hook abort every commit that touches a .nix file —
      # a chain that stayed invisible for as long as commits were docs-only.
      # No host builds on darwin; these two outputs are the whole reason it is
      # listed.
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # Shared by every host. Host-specific configuration — hostName,
      # stateVersion, hardware, display stack — lives in hosts/<host>/.
      # Deliberately a plain list, not a mkSystem helper: at three hosts with no
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
        # sops-nix: declarative secrets. Inert on any host that declares no
        # sops.* options — the module's config block is
        # `mkIf (cfg.secrets != {})`, so hplaptop imports it but gets nothing
        # from it (it is deliberately not a secret recipient). Kept in
        # commonModules (not per-host) so the option tree exists everywhere
        # and a host opting in later is a one-line change.
        sops-nix.nixosModules.sops
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
        };
        modules = commonModules ++ [
          ./hosts/vm
        ];
      };

      nixosConfigurations.geekom = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          user = users.geekom;
        };
        modules = commonModules ++ [
          ./hosts/geekom
        ];
      };

      nixosConfigurations.hplaptop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          user = users.hplaptop;
        };
        modules = commonModules ++ [
          ./hosts/hplaptop
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

      # `nix fmt` execs this with exactly the args it was given — Nix injects
      # no path (nix 2.34 formatter.cc). With plain `nixfmt`, a *bare* `nix fmt`
      # therefore parses STDIN as Nix code (nixfmt Main.hs: no files →
      # stdioTarget), so an empty/closed stdin dies with "unexpected end of
      # input" and an interactive bare invocation blocks instead of formatting
      # anything. `nixfmt-tree` is the upstream-blessed wrapper (treefmt
      # configured to run nixfmt over the repo, PRJ_ROOT-aware) that makes a
      # bare `nix fmt` format the flake root — which is what this entry has
      # always promised. Same nixfmt binary underneath: `nix fmt`, conform.nvim
      # and the pre-commit hook still agree with each other by construction.
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      # Minimal shell for hacking on this repo. On a NixOS host the only tool
      # here that is not already on the system profile (via
      # modules/home/neovim.nix) is deadnix — nixfmt, statix and nil are
      # duplicated so a fresh clone has a self-contained `nix develop` / direnv
      # that does not depend on having built and applied a host first. On the
      # darwin workstation NONE of them are otherwise present: no host module
      # applies there, so this shell is the only thing that puts them on PATH.
      # The pre-commit hook that .envrc installs runs `nixfmt` from this shell,
      # so the hook works on any clone, on any of the three systems.
      #
      # sops / ssh-to-age / age: present so secret edits (sops
      # secrets/andrea/secrets.yaml, recipient rekeying, age key inspection)
      # need no ad-hoc `nix shell`. Only the repo shell carries them — hosts
      # do not need the tools at runtime (sops-nix brings its own sops).
      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShellNoCC {
          packages = with nixpkgs.legacyPackages.${system}; [
            nixfmt
            statix
            nil
            deadnix
            sops
            ssh-to-age
            age
          ];
        };
      });
    };
}
