#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${AI_JAIL_HOME:-$HOME/.ai-jail}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found on PATH. Install Docker Desktop (macOS) first." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "docker daemon is not reachable. Start Docker Desktop first." >&2
  exit 1
fi

echo "==> linking $REPO_ROOT -> $TARGET"
if [ -L "$TARGET" ] || [ ! -e "$TARGET" ]; then
  rm -f "$TARGET"
  ln -s "$REPO_ROOT" "$TARGET"
elif [ -d "$TARGET" ] && [ "$(cd "$TARGET" && pwd)" = "$REPO_ROOT" ]; then
  : # already the repo itself
else
  echo "  $TARGET exists and is not a symlink to this repo. Leaving it alone."
fi

echo "==> building ai-jail image"
"$REPO_ROOT/scripts/build.sh"

SHELL_RC=""
case "${SHELL##*/}" in
  zsh)  SHELL_RC="$HOME/.zshrc" ;;
  bash) SHELL_RC="$HOME/.bashrc" ;;
  *)    SHELL_RC="$HOME/.zshrc" ;;
esac

SRC_LINE="source \"$TARGET/scripts/ai-jail.sh\""
if [ -f "$SHELL_RC" ] && grep -Fq "$TARGET/scripts/ai-jail.sh" "$SHELL_RC"; then
  echo "==> $SHELL_RC already sources ai-jail.sh"
else
  echo "==> appending source line to $SHELL_RC"
  {
    printf '\n# ai-jail launcher\n'
    printf '%s\n' "$SRC_LINE"
  } >> "$SHELL_RC"
fi

cat <<EOF

ai-jail installed.
  Reload your shell:   exec \$SHELL -l
  Launch the jail:     ai-jail <path-to-project>
  One-shot command:    ai-jail <path> claude --version
  Reset credentials:   ai-jail reset-auth
EOF
