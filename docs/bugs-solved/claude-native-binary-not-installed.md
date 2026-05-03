# Bug: `claude` fails inside the jail with "native binary not installed"

## Symptom

A freshly built jail looked healthy — `claude` was on `$PATH`, `claude --help`
worked — but actually launching it returned:

```
Error: claude native binary not installed.

Either postinstall did not run (--ignore-scripts, some pnpm configs)
or the platform-native optional dependency was not downloaded
(--omit=optional).

Run the postinstall manually (adjust path for local vs global install):
  node node_modules/@anthropic-ai/claude-code/install.cjs

Or reinstall without --ignore-scripts / --omit=optional.
```

A direct `docker run --rm --entrypoint zsh ai-jail:local -lc 'claude --version'`
worked. Only the real `ai-jail <path>` flow (which goes through `docker
compose run`) failed. That mismatch is what told us the image was fine and
the runtime config was the culprit.

## Root cause

Two independent issues stacked on top of each other.

### 1. pnpm 10 blocks dependency postinstall scripts by default

`@anthropic-ai/claude-code` ships its platform-native binary via a
`postinstall` script (`install.cjs`). pnpm 10 changed the default to **block
dependency lifecycle scripts** for security and now requires explicit
opt-in via `pnpm approve-builds` or the `onlyBuiltDependencies` config.

The build log even printed the warning, but it scrolled past unnoticed:

```
Ignored build scripts: @anthropic-ai/claude-code@2.1.126.
Run "pnpm approve-builds -g" to pick which dependencies should be allowed
to run scripts.
```

So the global install left `claude-code` on disk **without** its native
binary. The CLI shim ran but bailed out the moment it tried to invoke the
binary.

### 2. The pnpm-store named volume shadowed the global install

Even after fixing #1 by running the postinstall manually in the Dockerfile,
the same error still happened — but only via `ai-jail`, not via direct
`docker run`. That's because [compose/docker-compose.yml](../../compose/docker-compose.yml)
mounted the `ai-jail-pnpm-store` named volume at the *entire* pnpm
directory:

```yaml
- ai-jail-pnpm-store:/home/agent/.local/share/pnpm   # too broad
```

`$PNPM_HOME` (= `/home/agent/.local/share/pnpm`) holds **three** things:

- the global bin shims (`claude`, `codex`)
- the global `node_modules` (where `install.cjs` placed the native binary)
- the content-addressed store (`store/`)

The volume's intent was caching the **store** across runs. By mounting the
parent directory, an empty volume on first run hid the bin shims and the
native binary that the image had carefully installed.

## Fix

Two changes, in the commit that solved this bug.

### Dockerfile — run the postinstall ourselves

[docker/Dockerfile](../../docker/Dockerfile) — after `pnpm add -g`,
explicitly invoke each package's `install.cjs` so the native binary
downloads regardless of pnpm's lifecycle policy:

```dockerfile
RUN pnpm add -g @anthropic-ai/claude-code @openai/codex \
    && root="$(pnpm root -g)" \
    && for pkg in @anthropic-ai/claude-code @openai/codex; do \
           if [ -f "$root/$pkg/install.cjs" ]; then \
               node "$root/$pkg/install.cjs"; \
           fi; \
       done
```

The existence check keeps it forward-compatible: packages that don't ship
an `install.cjs` (like `@openai/codex`) don't break the build.

### Compose — narrow the cache mount to just the store

[compose/docker-compose.yml](../../compose/docker-compose.yml) — point the
volume at the actual store subdirectory instead of `$PNPM_HOME`:

```yaml
- ai-jail-pnpm-store:/home/agent/.local/share/pnpm/store
```

The store still gets cached across runs (which is what the volume was
named for); the bin shims and global `node_modules` keep coming from the
image as intended.

## Verification

End-to-end through the actual compose path the `ai-jail` shell function
uses:

```sh
docker volume rm ai-jail-pnpm-store
AI_JAIL_WORKSPACE=/tmp/ai-jail-test USER_UID=$(id -u) USER_GID=$(id -g) \
  docker compose -f compose/docker-compose.yml run --rm jail \
  zsh -lc 'claude --version && codex --version'
# 2.1.126 (Claude Code)
# codex-cli 0.128.0
```

## Lessons for future bug docs

- When something works under `docker run` but fails under `docker compose
  run`, suspect a volume mount before suspecting the image.
- Read the full `pnpm add` output during builds. pnpm 10 emits the "Ignored
  build scripts" warning quietly and the build still succeeds.
- Named-volume mount points need to be *as narrow as possible*. Mounting
  one level too high silently hides image content.
