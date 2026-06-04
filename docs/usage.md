# Usage: one install, many projects

ai-jail is installed **once** and reused across every project you work on.
There is no per-project setup, no config to edit, and no re-install.

- [How the path argument works](#how-the-path-argument-works)
- [What's shared across projects](#whats-shared-across-projects)
- [What's isolated per project](#whats-isolated-per-project)
- [Subcommands](#subcommands)
- [Examples](#examples)
  - [1. First-time walkthrough](#1-first-time-walkthrough)
  - [2. Working on multiple projects in parallel](#2-working-on-multiple-projects-in-parallel)
  - [3. Non-interactive one-shots](#3-non-interactive-one-shots)
  - [4. Multi-language project (Go + Node + Python)](#4-multi-language-project-go--node--python)
  - [5. A typical agent session — files appear on the host, owned by you](#5-a-typical-agent-session--files-appear-on-the-host-owned-by-you)
- [What ai-jail does *not* do](#what-ai-jail-does-not-do)

## How the path argument works

The `ai-jail` shell function takes the project path as an argument on each
invocation
([scripts/ai-jail.sh](../scripts/ai-jail.sh)):

```sh
ai-jail ~/code/project-a           # mounts project-a at /workspace
ai-jail ~/code/project-b claude    # mounts project-b, runs claude
ai-jail                            # mounts $PWD
ai-jail /any/other/path            # anywhere on your host
```

Each invocation:

1. Resolves the path you gave it to an absolute path.
2. Passes it as `AI_JAIL_WORKSPACE` into `docker compose run --rm jail`.
3. Spins up a fresh container with **that** folder bind-mounted at
   `/workspace`.
4. Discards the container when you leave (`--rm`).

## What's shared across projects

- **The image** (`ai-jail:local`) — built once, reused forever.
- **Credential volumes** — you `/login` to `claude` / `codex` / `gh` **once**
  and every project uses those credentials. See the main
  [README](../README.md#first-time-logins).
- **Toolchain caches** — the `ai-jail-go` volume persists Go module cache
  and installed binaries (`~/go`) across runs.

## What's isolated per project

- **Only the folder you passed** is visible inside the container. The agent
  working on `project-a` literally cannot see `project-b` on the
  filesystem. Each run is a fresh container with exactly one folder
  mounted ([README isolation guarantees](../README.md#isolation-guarantees-v1)).

## Subcommands

| Command               | What it does                                                |
|-----------------------|-------------------------------------------------------------|
| `ai-jail --help`      | Show usage, subcommands, and examples.                      |
| `ai-jail build`       | Rebuild the image with current host UID/GID.                |
| `ai-jail update`      | Pull latest base image + refresh `claude` / `codex` to the latest npm `@latest`. |
| `ai-jail init [path]` | Drop `CLAUDE.md` + `AGENTS.md` templates into `path` (defaults to `$PWD`). |
| `ai-jail reset-auth`  | Remove the credential volumes (forces re-login).            |
| `ai-jail prune`       | Remove image + all named volumes. Destructive.              |

Source: [scripts/ai-jail.sh](../scripts/ai-jail.sh).

Typical day-to-day never needs any of these except `--help`. You'll
reach for the rest only when updating the base image, rotating
credentials, or uninstalling.

## Examples

End-to-end scenarios for working in ai-jail. The first three are also
in the [main README](../README.md#examples); the last two live here
because they're verbose.

### 1. First-time walkthrough

Set up a new project, log in to claude once, then work in it:

```sh
cd ~/code/my-app
ai-jail init                       # drop CLAUDE.md + AGENTS.md templates
ai-jail                            # enter the jail ($PWD mounts at /workspace)
```

Inside the jail:

```sh
AI-JAIL · my-app /workspace  14:23
❯ claude
# first time: claude prompts /login, opens a browser flow on your host
# complete the OAuth, you're back in the claude REPL
# ask it to do work; when done:
❯ exit
```

Next time you run `ai-jail ~/code/my-app`:

```sh
AI-JAIL · my-app /workspace  09:11
❯ claude
# straight into claude, no login needed — credentials are in the
# ai-jail-claude named volume, on disk but outside your host filesystem
```

Same flow applies to `codex` (`codex login`) and `gh` (`gh auth login`).
One login per CLI, persistent across every project.

### 2. Working on multiple projects in parallel

Each terminal jails into its own folder; the prompt tells you which.

Terminal A (working on the API):

```
$ ai-jail ~/code/api
AI-JAIL · api workspace on  main  14:23
❯ claude --print "review the last commit"
```

Terminal B (working on the landing page, same time):

```
$ ai-jail ~/code/landing-page
AI-JAIL · landing-page workspace on  feat/header  14:24
❯ codex exec "add a CTA button to the hero section"
```

Both run against the same image, the same credentials, but completely
separate `/workspace` mounts. An agent in terminal A literally cannot
see anything from `landing-page` (and vice versa) — each container only
has its own project folder mounted.

The project name + branch + clock in the prompt makes terminal-tabbing
unambiguous; you'll never confuse which jail you're typing in.

### 3. Non-interactive one-shots

For scripts, CI, or quick checks, pass the command after the path. The
jail spins up, runs the command, removes the container, and you're back
at your host shell:

```sh
# ask claude to review a diff and print the answer
ai-jail ~/code/api claude --print "summarize the last commit"

# have codex add tests non-interactively
ai-jail ~/code/api codex exec "add tests for the /healthz endpoint"

# gh copilot suggest
ai-jail ~/code/api gh copilot suggest "list the 10 largest files"

# run the project's test suite inside the jail
ai-jail ~/code/api go test ./...
ai-jail ~/code/api pnpm test
ai-jail ~/code/api python3 -m pytest
```

Each call uses `docker compose run --rm`, so:

- Container is destroyed when the command exits.
- Files written under `/workspace` appear on your host (owned by your
  user, no `sudo chown` dance).
- Anything written elsewhere in the container — `/tmp`, `~/.cache`,
  etc. — is gone with the container, except for the few paths backed by
  named volumes (`~/.claude`, `~/.codex`, `~/.config/gh`,
  `~/.local/share/keyrings`, `~/go`, `~/.cache`).

### 4. Multi-language project (Go + Node + Python)

ai-jail's image ships Go 1.26, Node 22 (npm + pnpm), and Python 3.11 —
all three available in the same shell at once. A project that uses
multiple toolchains doesn't need separate containers per language.

```sh
$ ai-jail ~/code/mixed-stack
AI-JAIL · mixed-stack /workspace  10:02
❯ ls
backend/   # Go API
frontend/  # Vite + React (pnpm)
scripts/   # Python helpers

❯ cd backend && go test ./... && cd ..
PASS
ok  github.com/example/api  0.412s

❯ cd frontend && pnpm install && pnpm run build && cd ..
# pnpm fetches into the in-image store
# (no host nm leakage; persists across runs via the agent home dir)

❯ python3 scripts/migrate.py --dry-run
ok: 12 migrations queued, 0 conflicts
```

Notes on persistence between sessions:

- **Go modules + installed binaries**: `~/go` is backed by the
  `ai-jail-go` named volume, so `go install`-ed CLIs and the module
  cache survive across `ai-jail` invocations.
- **Node / pnpm**: globally-installed packages in the image (`claude`,
  `codex`) survive of course. There is no per-user pnpm-store volume —
  if you `pnpm install` inside a project, the `node_modules` lives in
  `/workspace/node_modules` (which is your project folder on the host)
  and persists naturally.
- **Python**: no `pip` or `venv` is preconfigured. Install per-project:
  `python3 -m pip install --user <pkg>`, or use a project-local venv.

### 5. A typical agent session — files appear on the host, owned by you

This example demonstrates the practical payoff of UID/GID matching:
when an agent writes files inside the jail, those files land on your
host owned by *your* user, not `root`. No `sudo chown` dance.

```sh
$ ai-jail ~/code/blog
AI-JAIL · blog /workspace  16:55
❯ claude
# inside claude:
> Please add a new post in posts/2026-06-04-ai-jail.md with a 200-word
> intro and a section explaining UID/GID matching.

# claude edits the file
# you see it confirm "Wrote posts/2026-06-04-ai-jail.md"
❯ exit
```

Back on your host (a *separate* shell):

```sh
$ ls -l ~/code/blog/posts/2026-06-04-ai-jail.md
-rw-r--r--  1 yuryalencar  staff  2147 Jun  4 16:56 2026-06-04-ai-jail.md
```

Notice the owner is `yuryalencar`, not `root` or some stranger UID.
That's because the image was built with your host UID/GID baked into
the in-container `agent` user — so kernel-level "who owns this file"
checks agree on both sides of the container boundary. See
[uid-gid.md](uid-gid.md) for the full mechanism.

Same property in the other direction: if you create a file on your
host (`echo hello > ~/code/blog/note.md`), the agent inside the jail
can read and edit it without permission errors.

## What ai-jail does *not* do

These aren't on the roadmap; if you need them, ai-jail is the wrong
tool:

- **It is not a containerized IDE.** Editors run on your host as usual;
  ai-jail just isolates the *agent's view of the filesystem*. Open
  your project in VS Code / Cursor / Neovim normally on the host.
- **It does not restrict network egress.** Anything inside can reach
  the public internet. Allowlisting via an outbound proxy is on the
  roadmap.
- **It does not protect against kernel-level escapes.** Standard
  Docker isolation only. For higher assurance, run the container under
  a seccomp / AppArmor / gVisor profile (out of scope for v0.x).
- **It does not pre-seed project tooling.** `ai-jail init` only writes
  CLAUDE.md and AGENTS.md templates — it doesn't `pnpm install`,
  `go mod tidy`, or set up venvs. Run those normally inside the jail.
