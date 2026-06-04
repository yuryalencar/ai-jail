# Bug: pnpm 11's new global layout broke `claude` and `codex` at runtime

## Symptom

After running `ai-jail build` on an image that hadn't been rebuilt in a
while, launching `claude` inside the jail printed:

```
AI-JAIL · app workspace on  staging [$]  v22.22.3  14:12
❯ claude
/home/agent/.local/share/pnpm/bin/claude: 12: exec:
  /home/agent/.local/share/pnpm/bin/../global/v11/7-19e84bd0fef/node_modules/@anthropic-ai/claude-code/bin/claude.exe:
  not found
```

The shim resolved, the file path looked valid — but `exec` reported "not
found." Confusingly, `claude` from `docker run --rm ai-jail:local`
(bypassing the compose mounts) worked fine, while `claude` inside the
actual `ai-jail` jail did not.

## Root cause

Two independent changes converged. Either one alone would have produced
the same error.

### 1. pnpm 11 changed where global packages live

The Dockerfile pins pnpm via `corepack prepare pnpm@latest --activate`,
which over time pulled pnpm from 10 to 11. The global layout is
materially different between the two:

| Aspect | pnpm 10 | pnpm 11 |
|---|---|---|
| CLI shim | `$PNPM_HOME/claude` | `$PNPM_HOME/bin/claude` |
| `pnpm root -g` returns | `…/global/5/node_modules` | `…/global/v11` |
| Package available at `<root>/<pkg>` | yes | **no** — packages live behind hashed subdirs + symlinks into the store |

Our pre-existing postinstall step in
[docker/Dockerfile](../../docker/Dockerfile):

```dockerfile
RUN pnpm add -g @anthropic-ai/claude-code @openai/codex \
    && root="$(pnpm root -g)" \
    && for pkg in @anthropic-ai/claude-code @openai/codex; do \
           if [ -f "$root/$pkg/install.cjs" ]; then \
               node "$root/$pkg/install.cjs"; \
           fi; \
       done
```

Worked fine on pnpm 10. On pnpm 11, `$root/$pkg/install.cjs` is no
longer a real path — the package is reached via
`global/v11/<hash>/node_modules/<pkg>` symlinks. So `if [ -f ]` was
silently false, `install.cjs` never ran, and the native binary was
never downloaded into the `bin/` directory. The 500-byte `claude.exe`
the user hit on disk is a *stub script* the npm package ships, whose
entire body is `echo "Error: claude native binary not installed." >&2;
exit 1`. The shim exec'd that stub, sh tried to parse it as a script,
failed, and reported "not found." (`exec: not found` covers both
"missing file" and "missing interpreter".)

### 2. The pnpm-store volume now shadows package content

The compose file mounted a named volume for the pnpm store:

```yaml
- ai-jail-pnpm-store:/home/agent/.local/share/pnpm/store
```

In pnpm 10 this was harmless: the store held the content-addressed
download cache, while global packages lived in
`global/<version>/node_modules/`. Mounting the store dir as a volume
just persisted the cache across runs.

In pnpm 11, the *actual installed package content* lives under the
store. The symlinks at
`global/v11/<hash>/node_modules/<pkg>` all resolve into
`store/v11/links/<pkg>/<version>/.../node_modules/<pkg>`. So mounting
that store dir as an initially-empty named volume shadowed *every
package* the image had baked in — including `claude` and `codex`.

Why this only bit now: in pnpm 10 the volume mount was an
optimization. In pnpm 11 the same mount became a regression.

## Fix

Two changes plus a third for ongoing version freshness.

### Dockerfile: run install.cjs by find, not by guessed path

[docker/Dockerfile](../../docker/Dockerfile):

```dockerfile
RUN pnpm add -g @anthropic-ai/claude-code@latest @openai/codex@latest \
    && find "$PNPM_HOME" -path "*/node_modules/@anthropic-ai/claude-code/install.cjs" \
            -exec node {} \; \
    && find "$PNPM_HOME" -path "*/node_modules/@openai/codex/install.cjs" \
            -exec node {} \;
```

`find` doesn't care which pnpm layout is in use — it walks the tree
and runs install.cjs wherever it lives. Robust across pnpm major
versions.

The `@latest` suffix is for the next problem (see below); functionally
`pnpm add -g <pkg>` and `pnpm add -g <pkg>@latest` behave the same on a
fresh install. The annotation just makes the intent ("track latest")
explicit at the call site.

### Compose: remove the pnpm-store volume

[compose/docker-compose.yml](../../compose/docker-compose.yml) — drop
the mount and the volume declaration:

```diff
       - ai-jail-keyrings:/home/agent/.local/share/keyrings
-      - ai-jail-pnpm-store:/home/agent/.local/share/pnpm/store
       - ai-jail-go:/home/agent/go
```

```diff
   ai-jail-keyrings:
     name: ai-jail-keyrings
-  ai-jail-pnpm-store:
-    name: ai-jail-pnpm-store
   ai-jail-go:
```

[scripts/ai-jail.sh](../../scripts/ai-jail.sh) — drop the same name
from `ai-jail prune`'s `docker volume rm` list, and add the previously
missing `ai-jail-keyrings`:

```diff
       docker volume rm ai-jail-claude ai-jail-codex ai-jail-gh \
-                       ai-jail-pnpm-store ai-jail-go ai-jail-cache 2>/dev/null
+                       ai-jail-keyrings ai-jail-go ai-jail-cache 2>/dev/null
```

The pnpm-store volume was an early caching optimization that became
actively harmful at the pnpm 10→11 transition. ai-jail's main use case
(running AI agents in a sandbox) doesn't install many pnpm packages
inside the jail, so losing the cache between sessions is a non-issue.

### Make `ai-jail update` actually re-fetch CLIs

A separate, related issue: even after fixing #1, `ai-jail update`
wouldn't necessarily pull a newer claude-code if the Dockerfile text
hadn't changed. Docker's layer cache keys the `RUN pnpm add -g` step
on the Dockerfile line alone — not on what npm currently has at
`@latest`.

Fix: a build-arg cache-buster.

[docker/Dockerfile](../../docker/Dockerfile):

```dockerfile
ARG CLI_REFRESH=cached
RUN echo "CLI_REFRESH=$CLI_REFRESH" >/dev/null \
    && pnpm add -g @anthropic-ai/claude-code@latest @openai/codex@latest \
    && find ...
```

[scripts/ai-jail.sh](../../scripts/ai-jail.sh):

```sh
update)
  docker pull node:22-bookworm-slim || true
  "$AI_JAIL_HOME/scripts/build.sh" --pull \
    --build-arg "CLI_REFRESH=$(date +%s)"
  return $?
  ;;
```

`ai-jail build` uses the default ARG value (`cached`), so day-to-day
rebuilds stay fast. `ai-jail update` injects a timestamp, which changes
the ARG, invalidates the layer cache from that point down, and forces
`pnpm add -g` to actually run and resolve `@latest`.

Verified: re-running `build.sh --build-arg CLI_REFRESH=$(date +%s)`
back-to-back re-runs the `pnpm add` (you see `+ @anthropic-ai/claude-code
2.1.x` in the output), whereas plain `build.sh` skips that layer.

## Verification

End-to-end through the actual compose path the `ai-jail` shell function
uses, with a fresh volume state:

```sh
docker volume rm ai-jail-pnpm-store 2>/dev/null
AI_JAIL_WORKSPACE=/tmp/ai-jail-test USER_UID=$(id -u) USER_GID=$(id -g) \
  docker compose -f compose/docker-compose.yml run --rm jail \
  zsh -lc 'claude --version ; codex --version'
# 2.1.161 (Claude Code)
# codex-cli 0.136.0
```

## Migration for existing installs

```sh
git pull
ai-jail build         # picks up the Dockerfile fix
docker volume rm ai-jail-pnpm-store  # drop the orphan once
ai-jail <path>
claude                # works now
```

To grab a fresh CLI version any time later:

```sh
ai-jail update
```

## Lessons for future bug docs

- **A passing `docker run` against a broken `docker compose run` is a
  volume-shadow signal.** It's the third time this codebase has hit the
  same class of bug (the previous two are
  [claude-native-binary-not-installed.md](claude-native-binary-not-installed.md)
  and the over-broad pnpm-store mount). Whenever a CLI works under
  `docker run --rm ai-jail:local` but fails under `ai-jail <path>`,
  audit the volume mounts in `compose/docker-compose.yml` before
  suspecting anything else.
- **`corepack prepare pnpm@latest --activate` is a moving target.** It
  pulls a new pnpm whenever the base image layer rebuilds, and a pnpm
  major can quietly change the global install layout. Either pin pnpm
  explicitly (`pnpm@10.x`) or write postinstall steps that don't depend
  on layout assumptions. We chose the second (`find` over `pnpm root
  -g`).
- **Docker layer cache + `pnpm add -g <pkg>` is silently stale.** Same
  Dockerfile line + same base layer = same resolved version forever,
  no matter what npm publishes. Build-arg cache-busting on the
  intended-fresh layer is the cheapest fix; don't reach for
  `--no-cache` (it re-does the whole image).
