# Bug: `codex auth` fails with "Permission denied (os error 13)"

## Symptom

A freshly built jail looked healthy and `codex --version` worked, but the
moment `codex` tried to read or write its config it bailed:

```
AI-JAIL /workspace
❯ codex auth
WARNING: proceeding, even though we could not update PATH: Permission denied (os error 13)
Error loading configuration: Permission denied (os error 13)
```

The same root cause produces two visible symptoms:

- `WARNING: ... could not update PATH` — codex tried to append a line to a
  shell rc file under `$HOME` and got blocked.
- `Error loading configuration` — codex tried to read/create
  `~/.codex/config.toml` and got blocked.

## Root cause

Docker's named-volume initialization rule:

> If the volume's target directory **does not exist in the image** at build
> time, Docker creates it at runtime as `root:root`.
>
> If the target directory **does exist** in the image, Docker copies its
> contents and ownership into the volume on first mount, then preserves
> them.

[compose/docker-compose.yml](../../compose/docker-compose.yml) mounts three
credential volumes inside `/home/agent`:

```yaml
- ai-jail-claude:/home/agent/.claude
- ai-jail-codex:/home/agent/.codex
- ai-jail-gh:/home/agent/.config/gh
```

…but the Dockerfile only pre-created `/home/agent/.cache`,
`/home/agent/.config`, and `/home/agent/.local/share/pnpm`. Nothing
created `.claude`, `.codex`, or `.config/gh`. So Docker created them at
runtime with `root:root` ownership, and the in-container `agent`
(uid=501 gid=20) couldn't write to any of them.

Confirmed by inspecting ownership inside a fresh container:

```
drwxr-xr-x 1   0  0   .claude       ← root-owned
drwxr-xr-x 1   0  0   .codex        ← root-owned
drwxr-xr-x 1   0  0   .config/gh    ← root-owned
drwxr-xr-x 1 501 20   .cache        ← OK
drwxr-xr-x 1 501 20   .config       ← OK
drwxr-xr-x 1 501 20   .local        ← OK
```

The same trap was waiting for `claude /login` and `gh auth login` — both
would have failed for the identical reason as soon as anyone reached for
them.

## Fix

[docker/Dockerfile](../../docker/Dockerfile) — pre-create every credential
mount point in the same `mkdir -p` line that already handles the cache and
pnpm dirs. The next-line `chown -R agent:agent /home/agent` then covers
them, and Docker's volume initialization preserves that ownership.

```dockerfile
RUN corepack enable \
    && corepack prepare pnpm@latest --activate \
    && mkdir -p /home/agent/.local/share/pnpm/store \
                /home/agent/.cache \
                /home/agent/.config/gh \
                /home/agent/.claude \
                /home/agent/.codex \
    && chown -R agent:agent /home/agent
```

Three notes on what's intentional here:

- `.config/gh` is created (not just `.config`) because the gh volume
  attaches at the `gh` subdir specifically. Pre-creating only the parent
  isn't enough — Docker would still create the missing `gh/` as root.
- `.local/share/pnpm/store` is included because the previous bug fix
  narrowed the pnpm-store volume from `$PNPM_HOME` to `$PNPM_HOME/store`.
  Without pre-creating `store/`, the same root-owned-mount-point trap
  would happen there too.
- The `chown -R agent:agent /home/agent` is preserved as the catch-all,
  so any future home-dir contents added before this layer get the right
  ownership for free.

## Cleaning up stale volumes

If a developer hit this bug before the fix landed, the old credential
volumes on their machine still have root-owned content baked in. The
volume's contents are preserved across container runs, so a rebuild alone
won't clear it. They need to drop the volumes once:

```sh
docker volume rm ai-jail-claude ai-jail-codex ai-jail-gh
```

The `ai-jail reset-auth` subcommand does exactly this, so:

```sh
ai-jail reset-auth
```

is the user-facing equivalent. After that, the next `ai-jail <path>`
recreates the volumes against the now-agent-owned mount points and
ownership is correct.

## Verification

End-to-end through the actual compose path the `ai-jail` shell function
uses:

```sh
docker volume rm ai-jail-claude ai-jail-codex ai-jail-gh
AI_JAIL_WORKSPACE=/tmp/ai-jail-test USER_UID=$(id -u) USER_GID=$(id -g) \
  docker compose -f compose/docker-compose.yml run --rm jail \
  zsh -lc 'ls -lan /home/agent/ /home/agent/.config/ ; codex --version'
```

Expected:

- `.claude`, `.codex`, `.config/gh` all owned by `501 20` (agent).
- `codex --version` prints `codex-cli 0.128.0` with no PATH warning.

## Lessons for future bug docs

- A named-volume mount point that doesn't exist in the image gets created
  as `root:root`. Always pre-create every `target:` path in your compose
  file inside the Dockerfile, with the right ownership.
- "Permission denied" errors that appear only inside the jail (and only on
  paths that happen to be volume mounts) almost always trace back to this
  rule. Suspect mount-point ownership before suspecting the binary's
  config logic.
- `chown -R /home/agent` is a useful catch-all — but only catches dirs
  that already exist in the image at the time it runs. It does not paper
  over a volume-mount-point that's missing from the image.
