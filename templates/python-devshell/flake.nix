{
  description = "Per-project Python dev shell — uv + python3, pinned via flake.lock";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Minimal on purpose: Python + uv are the toolchain, and everything else
          # (ruff, pytest, pytorch, ...) installs into the project-local venv via
          # `uv sync` — NEVER into the Nix shell or via `pip install --user`. That
          # keeps pyproject.toml / uv.lock the single source of truth for Python
          # deps, and flake.lock the single source of truth for Python itself.
          #
          # Bump python3 -> python311 / python310 etc. IN THIS FILE to match what
          # the repo you cloned requires: that pin is what the flake exists to
          # enforce. UV_PYTHON points uv at THAT interpreter and
          # UV_PYTHON_DOWNLOADS=never stops it fetching a managed one behind your
          # back, so `uv sync` builds against this python or fails loudly.
          default = pkgs.mkShell {
            packages = [
              pkgs.python3
              pkgs.uv
            ];
            env = {
              UV_PYTHON = "${pkgs.python3}/bin/python3";
              UV_PYTHON_DOWNLOADS = "never";
            };
          };
        }
      );
    };
}
