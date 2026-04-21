# Configuration: per-project CLAUDE.md, shared skills

ai-jail cleanly separates **per-project** configuration (lives in the
project folder) from **global** configuration (lives in a Docker volume
shared across every project). This doc explains how that split works and
how to use it.

## Per-project: `CLAUDE.md`

`CLAUDE.md` lives in the **project root**, which is what gets bind-mounted
at `/workspace` inside the jail. Each project has its own — Claude Code
reads it automatically when started in that directory.

There's a helper for seeding new projects:
[scripts/ai-jail.sh:43-52](../scripts/ai-jail.sh#L43-L52),
[README.md:53](../README.md#L53):

```sh
cd ~/code/my-new-project
ai-jail init              # seeds CLAUDE.md + AGENTS.md from templates/
ai-jail                   # enter the jail; claude picks up CLAUDE.md automatically
```

Same pattern applies to anything you'd normally put in `.claude/` at the
project root (project-level skills, agents, settings) — all bind-mounted
and therefore scoped to that project.

## Shared across projects: skills (and more)

Inside the jail, `~/.claude` is the named Docker volume `ai-jail-claude`
([compose/docker-compose.yml:22](../compose/docker-compose.yml#L22)). That
volume persists across every `ai-jail <path>` run, regardless of which
project you mount. So anything living under `~/.claude/` inside the jail
is **shared globally**:

- `~/.claude/skills/` — user-level skills available in every project.
- `~/.claude/CLAUDE.md` — user-level system prompt that applies everywhere.
- Login tokens, settings, agents, etc.

Install a skill once (inside the jail), and it's available the next time
you run `ai-jail` against any folder.

## The two-tier model you get for free

| Scope           | Where it lives                                                          | Behavior                                                    |
|-----------------|-------------------------------------------------------------------------|-------------------------------------------------------------|
| **Per-project** | `CLAUDE.md`, `.claude/skills/`, `.claude/agents/` inside the project    | Only visible when you `ai-jail <that-project>`              |
| **Global**      | `~/.claude/skills/`, `~/.claude/CLAUDE.md` inside the jail              | Lives in the `ai-jail-claude` volume — available everywhere |

Same two-tier model Claude Code uses on bare metal. ai-jail simply maps
"user level" to a Docker volume instead of your host `$HOME`.

## Caveat: `reset-auth` and `prune` wipe global config

`ai-jail reset-auth` and `ai-jail prune` remove the `ai-jail-claude`
volume. Credentials are the advertised target, but **anything** under
`~/.claude/` goes with them — including your global skills and user-level
`CLAUDE.md`. If you have non-trivial global config, back it up before
running either command, or keep the source in a separate repo you can
re-install from.
