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
          # Minimal on purpose: Python + uv are the project's toolchain, and
          # everything else (ruff, pytest, pytorch, ...) installs into the
          # project-local venv via `uv sync` / `uv pip install -r
          # requirements.txt` — NEVER into the Nix shell or via `pip install
          # --user`. That keeps the project's pyproject.toml / uv.lock as the
          # single source of truth for Python deps, and the flake.lock as the
          # single source of truth for Python itself. A C compiler is already on
          # PATH from stdenv, so it needs no package of its own — and it has to
          # be there, because many AI-repo deps (orphaned wheels with C
          # extensions, torch's build scripts on non-cuda hosts) fall back to a
          # source build on aarch64/Linux.
          #
          # Bump python3 -> python311 / python310 etc. IN THIS FILE to match
          # what the repo you cloned requires: that is exactly the version pin
          # the flake exists to enforce. UV_PYTHON points uv at THAT
          # interpreter and UV_PYTHON_DOWNLOADS=never stops it from fetching a
          # managed one behind your back, so `uv sync` builds the venv against
          # this python or fails loudly. (pkgs.python3 in nixpkgs 26.05 points
          # at 3.13; pin a lower attribute explicitly if the repo needs an
          # older minor.)
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
