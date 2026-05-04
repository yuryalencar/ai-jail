# ai-jail shell function. Source from ~/.zshrc or ~/.bashrc.
# Usage:
#   ai-jail                 # mount $PWD into the jail, drop into zsh
#   ai-jail <path>          # mount <path>
#   ai-jail <path> <cmd...> # mount <path>, run <cmd> non-interactively
#   ai-jail build           # (re)build the image with current host UID/GID
#   ai-jail update          # pull base image + rebuild
#   ai-jail reset-auth      # wipe claude/codex/gh credential volumes
#   ai-jail init            # copy CLAUDE.md + AGENTS.md templates into $PWD
#   ai-jail prune           # remove image + all named volumes (destructive)

AI_JAIL_HOME="${AI_JAIL_HOME:-$HOME/.ai-jail}"

ai-jail() {
  local compose_file="$AI_JAIL_HOME/compose/docker-compose.yml"

  case "${1-}" in
    build)
      "$AI_JAIL_HOME/scripts/build.sh"
      return $?
      ;;
    update)
      docker pull node:22-bookworm-slim || true
      "$AI_JAIL_HOME/scripts/build.sh" --pull
      return $?
      ;;
    reset-auth)
      echo "Removing credential volumes: ai-jail-claude, ai-jail-codex, ai-jail-gh"
      docker volume rm ai-jail-claude ai-jail-codex ai-jail-gh 2>/dev/null
      return 0
      ;;
    prune)
      echo "Removing image and ALL ai-jail volumes. Continue? [y/N]"
      read -r ans
      [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "aborted"; return 1; }
      docker rmi ai-jail:local 2>/dev/null
      docker volume rm ai-jail-claude ai-jail-codex ai-jail-gh \
                       ai-jail-pnpm-store ai-jail-cache 2>/dev/null
      return 0
      ;;
    init)
      for f in CLAUDE.md AGENTS.md; do
        if [ -e "$PWD/$f" ]; then
          echo "skip: $f already exists"
        else
          cp "$AI_JAIL_HOME/templates/$f" "$PWD/$f" && echo "wrote $f"
        fi
      done
      return 0
      ;;
  esac

  local target="${1:-$PWD}"
  if [ ! -d "$target" ]; then
    echo "ai-jail: '$target' is not a directory" >&2
    return 1
  fi
  shift 2>/dev/null || true
  local workspace project tz
  workspace="$(cd "$target" && pwd)"
  project="$(basename "$workspace")"
  tz="${TZ:-}"
  if [ -z "$tz" ] && [ -L /etc/localtime ]; then
    tz="$(readlink /etc/localtime | sed -E 's|.*/zoneinfo/||')"
  fi

  if [ "$#" -gt 0 ]; then
    AI_JAIL_WORKSPACE="$workspace" AI_JAIL_PROJECT="$project" TZ="$tz" \
    USER_UID="$(id -u)" USER_GID="$(id -g)" \
      docker compose -f "$compose_file" run --rm jail "$@"
  else
    AI_JAIL_WORKSPACE="$workspace" AI_JAIL_PROJECT="$project" TZ="$tz" \
    USER_UID="$(id -u)" USER_GID="$(id -g)" \
      docker compose -f "$compose_file" run --rm jail
  fi
}
