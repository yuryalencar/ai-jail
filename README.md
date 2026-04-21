# ai-jail

A Docker-based sandbox ("jail") for running agentic coding CLIs — Claude Code,
OpenAI Codex, and GitHub Copilot CLI — against one project folder at a time,
without giving them your whole laptop.

## What you get

- **Per-project bind mount.** The agent only ever sees the folder you pointed
  it at — not `$HOME`, not your SSH keys, not other projects.
- **Credentials in named Docker volumes.** `~/.claude`, `~/.codex`, and
  `~/.config/gh` live inside volumes, so logins persist across sessions but
  never touch your host filesystem.
- **UID-matched non-root user.** Files the agent writes are owned by *you* on
  the host — no `sudo chown` dance.
- **Three CLIs preinstalled** via `pnpm` + `gh` extension: `claude`, `codex`,
  `gh copilot`.
- **Professional shell** — zsh, starship prompt with an `AI-JAIL` marker,
  tmux, ripgrep, fd, git, gh.

## Requirements

- macOS or Linux host with Docker (Docker Desktop on macOS).
- zsh or bash login shell.

## Install

```sh
cd /Users/yuryalencar/Documents/ai-projects/ai-jail
./scripts/install.sh
exec $SHELL -l
```

The installer:
1. Symlinks this repo to `~/.ai-jail`.
2. Builds the `ai-jail:local` image with your host UID/GID.
3. Appends a `source ~/.ai-jail/scripts/ai-jail.sh` line to your shell rc.

## Daily use

```sh
ai-jail ~/code/my-project          # interactive zsh in the jail
ai-jail ~/code/my-project claude   # run claude non-interactively
ai-jail                             # uses $PWD
```

Subcommands:

| Command             | What it does                                           |
|---------------------|--------------------------------------------------------|
| `ai-jail build`     | Rebuild the image with current host UID/GID.           |
| `ai-jail update`    | Pull latest base image + rebuild.                      |
| `ai-jail init`      | Drop `CLAUDE.md` + `AGENTS.md` templates into `$PWD`.  |
| `ai-jail reset-auth`| Remove the three credential volumes (forces re-login). |
| `ai-jail prune`     | Remove image + all named volumes. Destructive.         |

## First-time logins

Inside the jail:

```sh
claude              # then /login
codex login
gh auth login       # required before gh copilot works
gh copilot suggest "list the 10 largest files"
```

Credentials persist in named volumes, so you only do this once per tool.

## Isolation guarantees (v1)

- No bind mount of `$HOME`, SSH keys, or the Docker socket.
- The agent sees `/workspace` (= your chosen folder) and nothing else of the
  host filesystem.
- Network egress is **open** in v1 — the agent can reach the public internet.
  Allowlisting is on the roadmap (see *Out of scope*).

## What the jail does **not** protect against (yet)

- **Open network.** Any process inside can talk to any public host. If you
  need stricter control, run the container on a Docker network with an egress
  proxy.
- **Kernel-level escapes.** Standard Docker isolation only. No seccomp,
  AppArmor, or gVisor profile in v1.
- **Supply chain.** The image pulls from Debian, npm, pnpm, starship, and gh
  upstreams at build time. Pin digests if that matters for you.

## Layout

```
ai-jail/
├── docker/         Dockerfile, entrypoint
├── compose/        docker-compose.yml (bind mount + named volumes)
├── scripts/        ai-jail.sh (shell fn), build.sh, install.sh
├── config/         zshrc, starship.toml, tmux.conf (copied into image)
├── templates/      CLAUDE.md + AGENTS.md seeds (ai-jail init)
└── docs/           in-depth docs (see below)
```

## More docs

- [docs/installation.md](docs/installation.md) — What install changes on
  your host, and how to fully uninstall.
- [docs/usage.md](docs/usage.md) — Using one install across many projects.
- [docs/configuration.md](docs/configuration.md) — Per-project `CLAUDE.md`
  vs. globally-shared skills.

## Out of scope for v1 (roadmap)

- Egress allowlist via an outbound proxy.
- Python / Go / Rust toolchains (add a `Dockerfile.full` variant).
- VS Code devcontainer wrapper.
- Seccomp / AppArmor profiles, read-only root FS.

## Troubleshooting

**"docker daemon is not reachable"** — Start Docker Desktop, wait for the
whale icon to go steady, re-run `./scripts/install.sh`.

**"required variable AI_JAIL_WORKSPACE is missing a value" during install
or `ai-jail build`** — Fixed. Earlier versions shelled the image build
through `docker compose build`, which interpolates the runtime bind-mount
variable even at build time. `scripts/build.sh` now uses `docker build`
directly (building is workspace-agnostic), and `ai-jail build` / `ai-jail
update` delegate to it. If you still hit this, pull the latest repo and
re-run `./scripts/install.sh`.

**Files written inside the jail are owned by root on host** — The image was
built with the wrong UID/GID. Run `ai-jail build` to rebuild with your
current user.

**`claude` / `codex` not found inside the jail** — pnpm's global bin dir
isn't on PATH. Check `echo $PNPM_HOME` — it should be
`/home/agent/.local/share/pnpm` and on `$PATH`.

**Want to wipe and start clean** — `ai-jail prune` removes the image and
every named volume.
