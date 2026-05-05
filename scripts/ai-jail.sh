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
    -h|--help|help)
      cat <<'EOF'
ai-jail — Docker sandbox for agentic coding CLIs (claude, codex, gh copilot).

USAGE
  ai-jail                      Mount $PWD into the jail, drop into zsh.
  ai-jail <path>               Mount <path> into the jail.
  ai-jail <path> <cmd...>      Mount <path>, run <cmd> non-interactively.

SUBCOMMANDS
  build         (Re)build the image with the current host UID/GID.
  update        Pull the latest base image and rebuild.
  init [path]   Drop CLAUDE.md + AGENTS.md templates into <path>
                (defaults to $PWD).
  reset-auth    Wipe the claude / codex / gh credential volumes (forces
                re-login next time).
  prune         Remove the image and ALL ai-jail named volumes. Destructive.
  help, -h, --help
                Show this message.

EXAMPLES
  ai-jail ~/code/my-project          # interactive zsh in the jail
  ai-jail ~/code/my-project claude   # run claude non-interactively
  ai-jail                            # uses $PWD
  ai-jail build                      # after changing the Dockerfile

DOCS
  Repo: https://github.com/yuryalencar/ai-jail
EOF
      return 0
      ;;
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
      local init_target="${2:-$PWD}"
      if [ ! -d "$init_target" ]; then
        echo "ai-jail init: '$init_target' is not a directory" >&2
        return 1
      fi
      init_target="$(cd "$init_target" && pwd)"
      for f in CLAUDE.md AGENTS.md; do
        if [ -e "$init_target/$f" ]; then
          echo "skip: $init_target/$f already exists"
        else
          cp "$AI_JAIL_HOME/templates/$f" "$init_target/$f" \
            && echo "wrote $init_target/$f"
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
