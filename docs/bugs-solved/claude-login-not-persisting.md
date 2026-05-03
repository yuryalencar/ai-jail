# Bug: Claude login does not persist across `ai-jail` runs

## Symptom

After successfully running `claude /login`, exiting the jail, and re-entering
with `ai-jail <path>`, claude immediately drops the user back at the
onboarding screen:

```
Select login method:

 ❯ 1. Claude account with subscription · Pro, Max, Team, or Enterprise
   2. Anthropic Console account · API usage billing
   3. 3rd-party platform · Amazon Bedrock, Microsoft Foundry, or Vertex AI
```

Codex (which uses simple file-based credentials) persisted fine. Only
claude was asking to log in every session.

## Root cause

Three independent issues, each one masking the next. Fixing only one or
two of them still leaves the symptom intact, which is why the bug looked
like "the volumes aren't persisting" at first.

### 1. `docker-compose` was prefixing volume names

[scripts/ai-jail.sh](../../scripts/ai-jail.sh) and the README refer to the
named volumes as `ai-jail-claude`, `ai-jail-codex`, etc. But docker-compose
auto-prefixes volumes with the project name (the parent directory of the
compose file), so the actual volumes on disk were
`compose_ai-jail-claude`, `compose_ai-jail-codex`, etc.

Two consequences:

- `ai-jail reset-auth` and `ai-jail prune` did `docker volume rm
  ai-jail-...` on names that did not exist. They were silent no-ops.
- Anyone trying to debug by running `docker volume ls | grep ai-jail-`
  saw confusing duplicates if they migrated.

Confirmed by `docker volume ls`:

```
local     compose_ai-jail-cache
local     compose_ai-jail-claude
local     compose_ai-jail-codex
local     compose_ai-jail-gh
local     compose_ai-jail-pnpm-store
```

This wasn't the credential-persistence bug per se — credentials *were*
being saved to those prefixed volumes — but it's what made the situation
unrecoverable: `ai-jail reset-auth` couldn't actually wipe anything, and
post-fix migration needed a deliberate rename.

### 2. No Secret Service for libsecret

Claude Code on Linux uses libsecret to persist OAuth tokens. The image
had `libsecret` clients (transitively, via Node) but no Secret Service
implementation: no DBus session bus, no `gnome-keyring-daemon`. Strings
inside the claude binary literally say:

```
libsecret not available
```

When `claude /login` completed the OAuth flow, the token couldn't be
stored anywhere persistent, so the next session had no credentials and
walked the user back through `/login`.

The binary does have a file fallback at `~/.claude/.credentials.json`,
but it's only used after libsecret first reports as unavailable; in
practice it was being written inconsistently and not always read on
startup.

### 3. `~/.claude.json` lives outside the persisted volume

This is the one that survived the first two fixes and produced the
"login again" symptom we kept seeing.

Claude Code stores its **user config** (subscription type, onboarding
completion, project history, preferences) in a single file at
`~/.claude.json`. Note the path: it is a *sibling* of `~/.claude/`, not a
file inside it.

Our compose file mounts the credential volume at `~/.claude/`. That
volume catches everything *under* the directory — `.credentials.json`,
`backups/`, `projects/`, `sessions/` — but not the `~/.claude.json`
file at the home root. Every new container started with a missing
`~/.claude.json`, so claude treated the user as un-onboarded and
re-displayed the login screen. Even though the OAuth tokens were
present in the keyring after fix #2, they weren't enough to get past
the onboarding gate.

Confirmed by `claude --print "..."` working (auth was present and
valid) while interactive `claude` immediately showed the onboarding
screen (config gate failing).

## Fix

Three changes, applied together.

### Compose: explicit volume names

[compose/docker-compose.yml](../../compose/docker-compose.yml) — pin every
named volume to its canonical name so docker-compose doesn't add a
project prefix:

```yaml
volumes:
  ai-jail-claude:
    name: ai-jail-claude
  ai-jail-codex:
    name: ai-jail-codex
  ai-jail-gh:
    name: ai-jail-gh
  ai-jail-keyrings:
    name: ai-jail-keyrings
  ai-jail-pnpm-store:
    name: ai-jail-pnpm-store
  ai-jail-cache:
    name: ai-jail-cache
```

`ai-jail reset-auth` and `ai-jail prune` now hit the right volumes.

### Dockerfile: install a Secret Service stack

[docker/Dockerfile](../../docker/Dockerfile) — add the libsecret library,
the `secret-tool` CLI (for debugging from inside the jail), a keyring
daemon, and the DBus session-bus tooling:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
        ... \
        libsecret-1-0 libsecret-tools gnome-keyring dbus-x11 \
        ...
```

A new mount point is also pre-created (per the same named-volume-ownership
rule documented in [codex-permission-denied.md](codex-permission-denied.md)):

```dockerfile
&& mkdir -p /home/agent/.local/share/keyrings ...
```

[compose/docker-compose.yml](../../compose/docker-compose.yml) — adds the
matching named volume:

```yaml
- ai-jail-keyrings:/home/agent/.local/share/keyrings
```

### Entrypoint: bring up DBus + keyring, redirect ~/.claude.json

[docker/entrypoint.sh](../../docker/entrypoint.sh) — start the DBus
session bus, start `gnome-keyring-daemon` with a fixed unlock password,
and symlink the user-config file into the persisted volume:

```bash
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
  fi
  eval "$(printf 'ai-jail\n' | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null)" || true
  eval "$(printf 'ai-jail\n' | gnome-keyring-daemon --start  --components=secrets 2>/dev/null)" || true
  export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK
fi

if [ ! -e "$HOME/.claude.json" ] || [ -L "$HOME/.claude.json" ]; then
  ln -sfn "$HOME/.claude/.claude.json" "$HOME/.claude.json"
fi
```

Notes on the design choices:

- **Fixed keyring password.** The keyring file is already protected by
  the host filesystem and the named volume. A real password would just
  block headless auto-unlock without adding a real boundary, since
  whatever derives that password also has to live somewhere accessible
  to the entrypoint. `ai-jail` is a deliberate, well-known constant.
- **`--unlock` then `--start`.** The first call no-ops if no daemon is
  running; the second starts a fresh one. Together they handle both
  "first ever session" and "subsequent session" without any branching.
- **Symlink, not bind mount.** A symlink keeps the change inside the
  container and stays compatible with claude reading/writing through
  the path. `bash -c '[ -L "$HOME/.claude.json" ]'` makes the entrypoint
  idempotent — replacing an existing symlink (e.g., from a prior fix
  attempt) but leaving a real file in place if the user put one there.

## One-time migration for existing installs

Developers who hit this bug before the fix landed have data in the old
prefixed volumes. The migration runs once:

```sh
# Move codex auth out of the old prefixed volume into the new canonical name.
# (Claude credentials predating the keyring fix are unusable; just discard them.)
docker volume create ai-jail-codex >/dev/null
docker run --rm \
  -v compose_ai-jail-codex:/from \
  -v ai-jail-codex:/to \
  alpine sh -c 'cp -a /from/. /to/'

# Drop the orphan prefixed volumes.
docker volume rm \
  compose_ai-jail-claude compose_ai-jail-codex compose_ai-jail-gh \
  compose_ai-jail-pnpm-store compose_ai-jail-cache
```

After that, `claude /login` once inside the jail and the post-login state
writes through the new keyring + symlink into the persisted volumes.

## Verification

1. `secret-tool` round-trip across two container runs (proves the keyring
   is a Secret Service that actually persists):

   ```sh
   docker volume rm ai-jail-keyrings
   AI_JAIL_WORKSPACE=/tmp/ai-jail-test USER_UID=$(id -u) USER_GID=$(id -g) \
     docker compose -f compose/docker-compose.yml run --rm jail bash -lc \
     'secret-tool store --label=test ai-jail probe <<<"persisted-secret-value"'

   AI_JAIL_WORKSPACE=/tmp/ai-jail-test USER_UID=$(id -u) USER_GID=$(id -g) \
     docker compose -f compose/docker-compose.yml run --rm jail bash -lc \
     'secret-tool lookup ai-jail probe'
   # → persisted-secret-value
   ```

2. `~/.claude.json` symlink is present and points into the volume:

   ```
   lrwxrwxrwx 1 agent agent /home/agent/.claude.json -> /home/agent/.claude/.claude.json
   ```

3. After completing one `claude /login` interactively, exiting, and
   re-entering, `claude` opens straight to the prompt with no login
   screen and no "configuration file not found" warning.

## Lessons for future bug docs

- Volume-name persistence and credential-store persistence are two
  different problems. Verify each independently — `docker volume ls` for
  the first, then file content inspection for the second — before
  assuming one is broken.
- "Logged-in CLI keeps re-prompting on Linux" is almost always a missing
  Secret Service. The CLI's binary will say `libsecret not available` or
  similar; install `gnome-keyring` + `dbus-x11` and start them in the
  entrypoint.
- Single-file home-dir state (`~/.claude.json`, `~/.npmrc`,
  `~/.gitconfig`) is the pattern that bind-mount-by-directory misses
  every time. When mounting `~/.foo/`, audit whether `~/.foo` (no
  trailing slash, single file) also exists and needs separate handling.
- A symlink from a fixed home path into a volume-backed directory is the
  cheapest fix for that pattern. Don't add a bind mount per file.
