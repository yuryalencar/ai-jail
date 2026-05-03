#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.config/gh" "$HOME/.cache" \
         "$HOME/.local/share/pnpm" "$HOME/.local/share/keyrings"

# Claude Code stores user config at ~/.claude.json (single file, sibling of
# ~/.claude/). That path falls outside the ai-jail-claude volume mount, so
# every container loses the config — onboarding re-runs and the user sees
# repeated "configuration file not found" warnings. Redirect the file into
# the persisted .claude/ volume by symlinking it.
if [ ! -e "$HOME/.claude.json" ] || [ -L "$HOME/.claude.json" ]; then
  ln -sfn "$HOME/.claude/.claude.json" "$HOME/.claude.json"
fi

# Bring up a session DBus + gnome-keyring so libsecret-backed CLIs (claude
# code) can persist OAuth tokens to ~/.local/share/keyrings/. The keyring
# password is fixed at "ai-jail" because the keyring file is already
# protected by the host filesystem + the named volume — there is no
# additional security boundary to defend with a real password here, and a
# fixed one is what makes auto-unlock viable in a headless container.
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
  fi
  eval "$(printf 'ai-jail\n' | gnome-keyring-daemon --unlock --components=secrets 2>/dev/null)" || true
  eval "$(printf 'ai-jail\n' | gnome-keyring-daemon --start  --components=secrets 2>/dev/null)" || true
  export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK
fi

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if ! gh extension list 2>/dev/null | grep -q 'github/gh-copilot'; then
    gh extension install github/gh-copilot >/dev/null 2>&1 || true
  fi
fi

exec "$@"
