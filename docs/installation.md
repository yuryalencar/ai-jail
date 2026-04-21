# Installation: what actually happens

Running `./scripts/install.sh` makes a small, well-defined set of changes to
your host — and nothing else. This doc enumerates every change so you know
exactly what you're agreeing to.

## Changes made to your host

### 1. Symlink created

- `~/.ai-jail` → the repo you cloned (e.g.
  `/Users/yuryalencar/Documents/ai-projects/ai-jail`).
- Source: [scripts/install.sh:17-25](../scripts/install.sh#L17-L25).
- Just a pointer. No files are copied.

### 2. One line appended to your shell rc

- `~/.zshrc` (or `~/.bashrc`) gets:
  `source "~/.ai-jail/scripts/ai-jail.sh"`.
- Source: [scripts/install.sh:37-46](../scripts/install.sh#L37-L46).
- This is what makes the `ai-jail` command available in new shells. It is
  a **shell function**, not a binary — nothing is installed to
  `/usr/local/bin` or similar.

### 3. Docker image built locally

- Image tag: `ai-jail:local`, ~1–1.5 GB.
- Base: `node:22-bookworm-slim` plus zsh, tmux, ripgrep, fd, git, gh,
  starship, and the `claude` / `codex` / `gh copilot` CLIs.
- Lives inside Docker, not loose on your filesystem.

### 4. Nothing else

- No system packages installed on your Mac.
- No changes to `$PATH`, `/usr/local`, `/etc`, or launch agents.
- No background processes. No ports opened.
- No SSH keys or `$HOME` exposed to the container.

## Created later, on first use (not during install)

When you first run `ai-jail <path>`, Docker creates five **named volumes**
(managed by Docker, not loose files on disk):

- `ai-jail-claude`, `ai-jail-codex`, `ai-jail-gh` — credential persistence,
  so you only `/login` once per tool.
- `ai-jail-pnpm-store`, `ai-jail-cache` — speeds up repeat runs.

The project folder you pass as an argument is **bind-mounted** read-write
into `/workspace` inside the container, so files the agent writes there
appear in that folder on your host (owned by your UID, per
[docker/Dockerfile:4-5](../docker/Dockerfile#L4-L5)).

## How to fully uninstall

```sh
ai-jail prune                       # removes image + all named volumes
rm ~/.ai-jail                       # removes the symlink
# then remove the `source ...ai-jail.sh` line from ~/.zshrc
```

That's a complete uninstall — your Mac is back to its prior state.

## What install does NOT do

From the main [README](../README.md#isolation-guarantees-v1):

- Does **not** mount `$HOME`, SSH keys, or the Docker socket.
- Does **not** restrict network egress — the container can reach the public
  internet.
- Does **not** apply seccomp / AppArmor / gVisor profiles (standard Docker
  isolation only).
