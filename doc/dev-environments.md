# Per-project dev environments

Per-project toolchains live _with each project_ as a Nix dev shell that direnv
loads automatically on `cd` — no global installs, no `nvm use`, every repo pins
its own versions. The starting point is a flake template in this repo
(`templates/devshell/`, exposed as the `devshell` flake output), so a new
project is one command away:

```bash
cd ~/code/my-project
nfi                   # alias: nix flake init -t ~/dotfiles-nix#devshell
$EDITOR flake.nix     # add tools to `packages`, e.g. [ nodejs_24 ]
git add flake.nix     # flakes only see tracked files — stage before evaluating
direnv allow          # one-time trust; the shell now auto-loads on cd
```

Whatever you added (`node`, …) is now on `PATH` inside the project and gone
outside it. The template pins nixpkgs to the same release as this system flake,
so dev shells reuse store paths already on disk instead of re-downloading a
second nixpkgs.

> **Documented exceptions to "no global installs":** `nodejs`, `uv` and
> `python3` are on every dev host's *system* profile — as agent runtimes, not
> project toolchains. Agent workflows execute from `~/.agents/skills` and
> one-off agent scripting happens outside any project, where no devshell can
> supply an interpreter. None of this replaces a devshell for project code:
> global `pip install` fails by design on NixOS, and a project needing a
> flake-pinned Python uses `templates/python-devshell/` (`nfp`),
> which shadows this system interpreter with its own.

> Commit the generated `flake.lock` too: it pins the exact nixpkgs revision, so
> the shell is reproducible for anyone who builds the project.

The VM is headless, so reach a dev server from the Mac by forwarding its port
over SSH:

```bash
# on the Mac
ssh -L 5173:[::1]:5173 nixos    # then open http://localhost:5173
```

> **Vite binds IPv6.** Vite resolves `localhost` to `::1`, not `127.0.0.1`, so
> the forward target must be the v6 loopback `[::1]` — `-L 5173:localhost:5173`
> (or `127.0.0.1`) gives a blank page.

## Gotchas

- **Flakes ignore untracked files.** A new `flake.nix` is invisible to
  evaluation until it's `git add`ed — the error reads "path does not exist,"
  not "you forgot to stage." Modern Nix auto-marks untracked files as
  intent-to-add as a safety net, but that stages an _empty_ placeholder, so a
  real `git add` is still required to commit content.
- **`direnv allow` is one-time per project.** direnv never runs an `.envrc` it
  hasn't been told to trust, and only re-prompts when the file changes — a
  security boundary, since an `.envrc` runs arbitrary shell.
- **Non-interactive SSH gets no dev shell.** direnv's auto-load hooks the
  _interactive_ prompt only, so `ssh nixos 'cd proj && node …'` won't find the
  tools. Enter the shell explicitly: `nix develop --command node …`.
- **Gitignore `.direnv/`.** nix-direnv caches the evaluated environment there;
  it's machine-local and must never be committed.
- **Commit `.envrc` — unless it holds secrets.** The guarded `.envrc`
  (`if has nix; then use flake; fi`) is safe to commit and makes the shell
  reproducible on clone. But when a project uses `.envrc` to load a token
  (`export GH_TOKEN=…`), keep it gitignored — or move the secret into a
  gitignored `.env` and `dotenv_if_exists` it from a committed `.envrc`.

---

- Rebuild aliases used here (`nfi`): [doc/workflow.md](workflow.md)
- Common failure modes: [doc/troubleshooting.md](troubleshooting.md)
