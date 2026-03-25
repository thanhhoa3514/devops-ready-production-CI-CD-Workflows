#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.prod.yml"
ENV_FILE="$ROOT_DIR/ops/.env.production"
LOCK_FILE="/tmp/devops-tutorial-deploy.lock"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  echo "Copy ops/.env.production.example to ops/.env.production and update values."
  exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Missing compose file: $COMPOSE_FILE"
  exit 1
fi

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Another deployment is running."
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

if [[ -z "${DOCKERHUB_USERNAME:-}" ]]; then
  echo "DOCKERHUB_USERNAME is required in $ENV_FILE"
  exit 1
fi

IMAGE_TAG="${IMAGE_TAG:-latest}"
APP_PORT="${APP_PORT:-3000}"
CURRENT_IMAGE_TAG=""

set_env_value() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s#^${key}=.*#${key}=${value}#" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

wait_for_healthy() {
  echo "Waiting for health status..."
  for _ in {1..20}; do
    STATUS="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' devops-tutorial-app 2>/dev/null || true)"
    if [[ "$STATUS" == "healthy" ]]; then
      return 0
    fi
    sleep 3
  done

  return 1
}

if docker inspect devops-tutorial-app >/dev/null 2>&1; then
  CURRENT_IMAGE="$(docker inspect --format='{{.Config.Image}}' devops-tutorial-app 2>/dev/null || true)"
  if [[ -n "$CURRENT_IMAGE" && "$CURRENT_IMAGE" == *:* ]]; then
    CURRENT_IMAGE_TAG="${CURRENT_IMAGE##*:}"
  fi
fi

echo "Deploying docker.io/${DOCKERHUB_USERNAME}/devops-tutorial:${IMAGE_TAG}"
if [[ -n "$CURRENT_IMAGE_TAG" ]]; then
  echo "Current running tag: ${CURRENT_IMAGE_TAG}"
fi

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --remove-orphans --force-recreate

if wait_for_healthy; then
  echo "Deployment successful."
  exit 0
fi

echo "Container did not become healthy in time."
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps

if [[ -z "$CURRENT_IMAGE_TAG" ]]; then
  echo "Rollback skipped: could not determine previous running tag."
  exit 1
fi

if [[ "$CURRENT_IMAGE_TAG" == "$IMAGE_TAG" ]]; then
  echo "Rollback skipped: previous tag is the same as target tag (${IMAGE_TAG})."
  exit 1
fi

echo "Starting rollback to previous tag: ${CURRENT_IMAGE_TAG}"
set_env_value "IMAGE_TAG" "$CURRENT_IMAGE_TAG"

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --remove-orphans --force-recreate

if wait_for_healthy; then
  echo "Rollback successful. Service restored with tag ${CURRENT_IMAGE_TAG}."
else
  echo "Rollback failed. Service may be unavailable."
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps
fi

exit 1
