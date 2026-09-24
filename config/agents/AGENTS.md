# Global Agent Rules

Behavioural rules that apply to every session on the dev hosts (geekom, vm), in
every repo. Repo-specific conventions belong in that repo's `AGENTS.md`.
Source of truth: `config/agents/AGENTS.md` in the dotfiles-nix repo — this file
is installed read-only, so edit it there, never in place.

## Workflow

- Before starting multi-phase implementations, explicitly evaluate whether the
  problem justifies the complexity. Ask: "Is the existing setup already
  sufficient?" Don't build infrastructure for marginal value.
- When working on multi-phase implementations, STOP after completing the current
  phase/bug/task. Do not proceed to the next phase or task without explicit user
  approval. Always ask before moving on.
- When the user asks to save a checkpoint or stop, do exactly that. Do not
  investigate bugs, start new phases, or do additional work. Save the checkpoint
  with notes about known issues and exit.
- When asked to update PRDs or documentation, do that BEFORE committing code. Do
  not skip documentation updates in favor of jumping to implementation.
- During brainstorming or research, do NOT jump to implementation (Edit/Write
  tool calls) without explicit user approval. Discussion and implementation are
  separate modes — wait for a clear go-ahead before writing code.
- Feature-specific blockers and status notes belong on the PRD (e.g. the `.dev/`
  master plan), not in persistent memory or long-lived notes. Memory is for
  cross-session context, not feature-specific state.
- Keep `AGENTS.md` (and equivalents like `CLAUDE.md`) small — durable behavioural
  rules and invariants only. Every word is loaded into every session's context.
  Architectural tours, rationales, and session insights belong in `README.md` or
  other repo docs. Before adding a line, ask: would a future session materially
  change behaviour because of it? If not, route it elsewhere.
- Multi-repo tasks: before editing files in a repository other than the current
  working directory, read that repo's `AGENTS.md` (and equivalents like
  `CLAUDE.md`) first. Conventions, layout, and toolchain can differ silently.
- When planning from an external requirement document (spec, brief, PDF), copy it
  into the PRD folder (e.g. `.dev/<feature>/reference/`) so later sessions read
  the source rather than a summary of it.

## Architecture & Design Reviews

- When asked to compare, analyze, or critically review PRDs or architecture, use
  parallel exploration agents for thorough coverage. Don't hold back on critical
  feedback.
- Give honest, specific pushback on architecture decisions. The user wants a
  sparring partner, not agreement. Point out fundamental flaws, tension points,
  and over-engineering — even if the initial work looks solid.

## Explaining Technical Work

- Before recommending or implementing anything technical, say what the thing
  **is** and what the **alternatives** were. The user forms the judgment; don't
  hand down conclusions. A verdict on its own can't be judged — comparison is
  what makes judgment possible.
- Never use framework, library, or API vocabulary without defining it on first
  use. Method names and library concepts are not assumed knowledge.
- When the user challenges a technical claim, re-verify it against primary
  documentation or an empirical test (compile it, run it) instead of defending
  it. Say plainly what changed.

## Coding Principles

- Prefer simple solutions. When fixing bugs, start with the simplest possible
  approach before proposing complex solutions. If the user suggests a simpler
  approach, adopt it immediately.
- When adding a gate (coverage threshold, lint rule, CI check), verify it fails
  before trusting that it passes. A gate never observed failing is
  indistinguishable from one that measures nothing.

## Environment & Tooling

- Docker exists on geekom only (`local.docker.enable`). `daemon.settings.ip`
  makes `docker run -p 8080:80` loopback-only, but only on the default bridge:
  a compose project's user-defined network ignores it, so its `ports:` entries
  each need an explicit `127.0.0.1:`. Opt into the LAN with `0.0.0.0:` instead.
- Never pass `--volumes` to `docker prune`/`docker system prune`. It deletes
  every volume not attached to a *running* container, so stopping a dev database
  container and then pruning silently wipes its data volume. Use scoped commands
  instead: `docker image prune -f` (dangling), `docker container prune -f`
  (stopped), `docker builder prune -af` (build cache). Remove volumes only with
  an explicit `docker volume rm <name>`.
- Secrets are sops-nix managed: plaintext exists only under `/run/secrets`
  (owned by the dev user, mode 0400, tmpfs — wiped at reboot). Never write a
  secret value into a repo file, a Nix file, or a shell command; the repo holds
  age-encrypted ciphertext (`secrets/andrea/secrets.yaml`) only. Read secrets at
  their point of use, e.g. `cat /run/secrets/<NAME>`.

## Git & PRs

- Squash-merge feature branches into the main branch (`main`/`master`): keeps
  history clean and each PR becomes one atomic commit.
- Contribute to existing PRs rather than proposing competing alternatives, and
  frame improvements as additions, not replacements. Keep PR comments focused:
  one idea with data, one open question. No laundry lists of prescriptions.
- PR bodies: read `skill://pr` first, and use its sections — Summary (diagram,
  diff or tree), Evidence (before → after), Merge Danger (door, blast radius).
- Before calling the working tree dirty or proposing a commit, verify the changed
  paths are tracked. `git status --porcelain` excludes gitignored paths; use
  `git check-ignore <path>` if uncertain. PRDs in `.dev/`, downloaded artifacts,
  and machine-local notes are gitignored work products — no commit decision
  needed. Don't ask "commit alongside?" for changes that aren't tracked.
- NEVER include in commits, PR titles, PR descriptions, PR comments, or any
  git-related output: AI-generated attribution (`Co-Authored-By`, "Generated
  with …", references to any model vendor or its `noreply` address) or emojis in
  commit messages.
