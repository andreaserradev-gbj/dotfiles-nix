{
  description = "Personal NixOs + Home Manager configuration — multi-host";

  inputs = {

    nixpkgs.url = "github:NixOs/nixpkgs/nixos-26.05";

    # The escape hatch (doc/workflow.md, "Need a newer version before the next
    # release?"): a second nixpkgs, consumed for a small explicit selection of
    # tools. It moves daily, so never reference it from shared code.
    nixpkgs-unstable.url = "github:NixOs/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # sops-nix follows our nixpkgs so the module pins to the sops/age versions the
    # system would build anyway — no second nixpkgs tree in the lockfile.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Not in nixpkgs, so the package comes from upstream's flake, TAG-PINNED —
    # an unpinned github: input moves on every `nfu`. This `?ref=` must stay a
    # literal (Nix's flake parser), so `nfb` (scripts/nfb.sh) rewrites it
    # together with the version and hashes in tool-pins.json.
    #
    # `nixpkgs` follows our unstable (the tree omp's own lock is cut against);
    # `nixpkgs-darwin-x64` follows stable instead, because that input only
    # matters for x86_64-darwin, which no host here is — following it raw would
    # add a third nixpkgs tree for zero benefit. What this repo installs is the
    # prebuilt release from tool-pins.json, not the from-source build (doc/omp.md).
    omp = {
      url = "github:can1357/oh-my-pi?ref=v18.3.1";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.nixpkgs-darwin-x64.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      sops-nix,
      omp,
      ...
    }:
    let
      users = import ./user.nix;

      # The systems that get developer-facing outputs (`formatter`, `devShells`),
      # NOT the systems that get hosts. aarch64-darwin is listed because the Mac
      # is where this repo is edited: without it `nix develop` fails, which makes
      # `.envrc`'s `use flake` fail, which leaves nixfmt off PATH, which makes
      # the pre-commit hook abort every commit touching a .nix file. No host
      # builds there.
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # Shared by every host; host-specific configuration (hostName, stateVersion,
      # hardware, display stack) lives in hosts/<host>/. A plain list rather than
      # a mkSystem helper: at three hosts with no builder divergence the helper
      # would be indirection for ~10 saved lines.
      #
      # Every seam module is here, including the ones only one host switches on,
      # because they DEFINE their `local.*` option: a host must be able to see an
      # option in order to leave it off. `user` is resolved per-host below, so
      # each host sees its own identity attrset via specialArgs; HM gets the same
      # attrset through extraSpecialArgs.
      commonModules = [
        ./modules/nixos/common.nix
        ./modules/nixos/desktop.nix
        ./modules/nixos/gaming.nix
        ./modules/nixos/docker.nix
        ./modules/nixos/dev.nix
        ./modules/nixos/loopback-rebuild.nix
        # Inert on a host that declares no `sops.*`: its config block is
        # `mkIf (cfg.secrets != {})`, and hplaptop is deliberately not a recipient.
        # Kept here so a host opting in later is a one-line change.
        sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        (
          {
            user,
            ...
          }:
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = {
              inherit user;
              # The flake INPUT, not the package: modules/home/omp.nix imports
              # omp's homeManagerModules.default, whose programs.omp.package
              # already defaults to self.packages.<system>.default — threading
              # the package too would be a second path to the same drv.
              inherit omp;
            };
            home-manager.users.${user.username} = import ./home.nix;
          }
        )
      ];
    in
    {
      # `unstablePkgs` is the second nixpkgs as the module arg the escape hatch
      # needs. legacyPackages, not `import` — the `system` import argument is
      # deprecated upstream. No allowUnfree wiring: the adopted packages (ollama,
      # opencode) are free software.
      #
      # It is passed to EVERY host because a shared module consumes it
      # (modules/nixos/dev.nix takes it for opencode), but the second tree is
      # evaluated lazily and forced only where a package references it:
      # ollama-vulkan in hosts/geekom/default.nix, and opencode behind dev.nix's
      # dev gate. hplaptop receives the binding and her closure does not move.
      # The rule: reference `unstablePkgs` from a host file, or from a shared
      # module ONLY behind the dev gate — never from shared code that every host
      # evaluates unconditionally.
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {
          user = users.nixos;
          unstablePkgs = nixpkgs-unstable.legacyPackages.aarch64-linux;
        };
        modules = commonModules ++ [
          ./hosts/vm
        ];
      };

      nixosConfigurations.geekom = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          user = users.geekom;
          unstablePkgs = nixpkgs-unstable.legacyPackages.x86_64-linux;
        };
        modules = commonModules ++ [
          ./hosts/geekom
        ];
      };

      nixosConfigurations.hplaptop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          user = users.hplaptop;
          unstablePkgs = nixpkgs-unstable.legacyPackages.x86_64-linux;
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

      # `nix fmt` execs this with exactly the args it was given. With plain
      # `nixfmt`, a bare `nix fmt` therefore parses STDIN as code and dies on an
      # empty stdin (or blocks interactively) instead of formatting anything.
      # `nixfmt-tree` is the upstream wrapper that makes a bare `nix fmt` format
      # the flake root — same nixfmt binary underneath, so `nix fmt`, conform.nvim
      # and the pre-commit hook still agree by construction.
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      # Minimal shell for hacking on this repo. On a NixOS host only deadnix is
      # otherwise missing; on the darwin workstation none of them are present, so
      # this shell is what puts them on PATH. The pre-commit hook `.envrc`
      # installs runs nixfmt from here, so it works on any clone on any system.
      #
      # sops / ssh-to-age / age are here so secret edits (sops
      # secrets/andrea/secrets.yaml, recipient rekeying, key inspection) need no
      # ad-hoc `nix shell`; hosts do not need them at runtime.
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
