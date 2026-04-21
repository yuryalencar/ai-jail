#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Build directly with `docker build`, not `docker compose build`. The compose
# file requires AI_JAIL_WORKSPACE for the runtime bind mount, and compose
# interpolates that variable even on `build`, forcing a workspace path to
# exist at build time. Building the image is workspace-agnostic, so we skip
# compose here and keep its enforcement for the `run` path where it matters.
docker build \
  --build-arg USER_UID="$(id -u)" \
  --build-arg USER_GID="$(id -g)" \
  -t ai-jail:local \
  -f "$REPO_ROOT/docker/Dockerfile" \
  "$@" \
  "$REPO_ROOT"

echo "ai-jail: image built (ai-jail:local) with UID=$(id -u) GID=$(id -g)"
