# AGENTS.md

Shared instructions for coding agents (OpenAI Codex CLI, GitHub Copilot CLI, and any
other agent that reads `AGENTS.md`). If an agent also reads `CLAUDE.md`, the two
should agree — keep them in sync.

## Project overview
<!-- One or two sentences. -->

## Setup
```sh
pnpm install
```

## How to run and test
- dev:   `pnpm dev`
- test:  `pnpm test`
- lint:  `pnpm lint`
- build: `pnpm build`

Always run `pnpm test` before declaring a change done.

## Code style
- Match the existing style; don't reformat unrelated code.
- Keep changes minimal and scoped to the task.
- No speculative abstractions or "while I'm here" refactors.

## Out of bounds
- Don't modify `.env*`, secrets, or CI credentials.
- Don't change `pnpm-lock.yaml` unless dependencies actually changed.
- Don't push, open PRs, or create issues without being asked.

## PR / commit etiquette
- One logical change per commit.
- Commit message: short imperative summary, then why.
