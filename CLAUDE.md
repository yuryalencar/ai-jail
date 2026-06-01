# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

**ai-jail** is a Docker-based sandbox for running agentic coding CLIs (Claude Code, OpenAI Codex, GitHub Copilot CLI) against a single project folder, without exposing the host's home directory, SSH keys, or other projects.

The repo is installed once on a developer's machine (`./scripts/install.sh`), which:
1. Symlinks the repo to `~/.ai-jail`
2. Builds a local Docker image (`ai-jail:local`) baked with the host user's UID/GID
3. Appends a `source ~/.ai-jail/scripts/ai-jail.sh` line to the shell rc

After that, `ai-jail <path>` is a shell function (not a binary) that spins up a fresh container with only that one path bind-mounted.

The image includes Node.js 22, Go (see `ARG GO_VERSION` in the Dockerfile), Python 3, and the standard Unix toolchain. All three are available inside the jail without any per-project setup.

## Layout

```
docker/         Dockerfile + entrypoint.sh
compose/        docker-compose.yml (volumes, bind mount, env)
scripts/        ai-jail.sh (the shell function), build.sh, install.sh
config/         zshrc, starship.toml, tmux.conf — copied into the image at build time
templates/      CLAUDE.md + AGENTS.md seeds dropped by `ai-jail init`
docs/           Deep-dives: uid-gid, installation, usage, configuration, bugs-solved/
```

## Key commands

```sh
./scripts/install.sh           # first-time install (needs Docker running)
./scripts/build.sh             # rebuild ai-jail:local with current host UID/GID
ai-jail build                  # same, via the shell function
ai-jail update                 # pull base image (node:22-bookworm-slim) + rebuild
ai-jail reset-auth             # wipe ai-jail-claude / ai-jail-codex / ai-jail-gh volumes
ai-jail prune                  # remove image + ALL named volumes (destructive)
ai-jail init [path]            # copy templates/CLAUDE.md + AGENTS.md into path
```

There are no test or lint commands — this is a shell + Docker project with no package.json.

## Architecture

### Image build (UID/GID baking)

The image is **built per machine**, not pulled from a registry. `build.sh` passes `$(id -u)` and `$(id -g)` as build args. The Dockerfile renames the existing `node` user to `agent` with those exact numbers. This makes files written inside `/workspace` appear on the host owned by the correct user — no `chown` needed. See `docs/uid-gid.md` for why macOS (UID 501, GID 20) needs extra logic to handle pre-existing GID conflicts in the Debian base image.

### Credential persistence (named Docker volumes)

Six named volumes are declared in `compose/docker-compose.yml` with explicit `name:` keys — this is critical. Without explicit names, docker-compose adds a project-name prefix, which breaks `ai-jail reset-auth` and `ai-jail prune` (they'd `docker volume rm` the wrong names). The volumes:

| Volume | Mounted at |
|---|---|
| `ai-jail-claude` | `~/.claude` |
| `ai-jail-codex` | `~/.codex` |
| `ai-jail-gh` | `~/.config/gh` |
| `ai-jail-keyrings` | `~/.local/share/keyrings` |
| `ai-jail-pnpm-store` | `~/.local/share/pnpm/store` |
| `ai-jail-go` | `~/go` (module cache + installed binaries) |
| `ai-jail-cache` | `~/.cache` (includes `go-build` cache) |

### Claude credential persistence quirks

Claude Code has two credential-persistence mechanisms that must both work:

1. **libsecret / gnome-keyring** — Claude Code on Linux stores OAuth tokens via the Secret Service API. The Dockerfile installs `gnome-keyring` + `dbus-x11`; `entrypoint.sh` starts a DBus session bus and unlocks the keyring with the fixed password `ai-jail` on every container start.

2. **`~/.claude.json` symlink** — Claude Code stores user config (onboarding state, subscription type) in `~/.claude.json`, which is a sibling of `~/.claude/`, not inside it. The `ai-jail-claude` volume is mounted at `~/.claude/`, so `~/.claude.json` would be lost on every restart. `entrypoint.sh` symlinks `~/.claude.json → ~/.claude/.claude.json` to redirect it into the persisted volume.

Both must be in place. Missing either one causes the "login prompt on every session" symptom. See `docs/bugs-solved/claude-login-not-persisting.md` for the full analysis.

### The shell function

`scripts/ai-jail.sh` defines the `ai-jail` shell function. It resolves the target path to absolute, exports `AI_JAIL_WORKSPACE`, `AI_JAIL_PROJECT`, `TZ`, `USER_UID`, and `USER_GID`, then calls `docker compose run --rm jail`. The compose file requires `AI_JAIL_WORKSPACE` to be set — it enforces this with `${AI_JAIL_WORKSPACE:?...}` so a missing value fails loudly rather than mounting an empty path. The image is **not** built via `docker compose build` because compose would require `AI_JAIL_WORKSPACE` to exist at build time too; `build.sh` calls `docker build` directly to avoid this.

### Config files baked into the image

`config/zshrc`, `config/starship.toml`, and `config/tmux.conf` are `COPY`-ed into the image. The starship prompt shows the `AI_JAIL_PROJECT` env var (set by the shell function from `basename` of the mounted path), git branch, and local time. The zshrc sets `AI_JAIL=1`, which can be tested inside jailed agents to detect they're running in the sandbox.

## Editing guidelines

- When modifying `compose/docker-compose.yml`, always include an explicit `name:` under each volume entry. Losing those names causes silent credential loss.
- When adding a new directory that needs to be volume-backed, create it in **both** the Dockerfile (`mkdir -p` before the `chown -R`) and `compose/docker-compose.yml`. Creating it only in the Dockerfile means Docker will create it as root on first mount.
- After changing the Dockerfile or config files, run `ai-jail build` to apply changes.
- `entrypoint.sh` runs as the `agent` user (the `USER agent` directive is set before `WORKDIR /workspace`). Keep it idempotent — it runs on every container start.
