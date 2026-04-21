# Usage: one install, many projects

ai-jail is installed **once** and reused across every project you work on.
There is no per-project setup, no config to edit, and no re-install.

## How the path argument works

The `ai-jail` shell function takes the project path as an argument on each
invocation
([scripts/ai-jail.sh:55-72](../scripts/ai-jail.sh#L55-L72)):

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
- **pnpm store / cache volumes** — speed up repeated use across projects.

## What's isolated per project

- **Only the folder you passed** is visible inside the container. The agent
  working on `project-a` literally cannot see `project-b` on the
  filesystem. Each run is a fresh container with exactly one folder
  mounted ([README isolation guarantees](../README.md#isolation-guarantees-v1)).

## Subcommands (when you do touch the install)

| Command              | What it does                                           |
|----------------------|--------------------------------------------------------|
| `ai-jail build`      | Rebuild the image with current host UID/GID.           |
| `ai-jail update`     | Pull latest base image + rebuild.                      |
| `ai-jail init`       | Drop `CLAUDE.md` + `AGENTS.md` templates into `$PWD`.  |
| `ai-jail reset-auth` | Remove the three credential volumes (forces re-login). |
| `ai-jail prune`      | Remove image + all named volumes. Destructive.         |

Source: [scripts/ai-jail.sh](../scripts/ai-jail.sh).

Typical day-to-day never needs any of these. You'll reach for them only
when updating the base image, rotating credentials, or uninstalling.

## Typical flow for a new project

```sh
cd ~/code/my-new-project
ai-jail init              # seed CLAUDE.md + AGENTS.md (optional)
ai-jail                   # enter the jail, $PWD is mounted at /workspace
# inside the jail:
claude                    # (first time only: /login)
```

No new volumes, no new image, no install step.
