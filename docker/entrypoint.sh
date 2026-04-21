#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.config/gh" "$HOME/.cache" \
         "$HOME/.local/share/pnpm"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if ! gh extension list 2>/dev/null | grep -q 'github/gh-copilot'; then
    gh extension install github/gh-copilot >/dev/null 2>&1 || true
  fi
fi

exec "$@"
