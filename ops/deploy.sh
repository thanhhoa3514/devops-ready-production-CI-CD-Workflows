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

echo "Deploying docker.io/${DOCKERHUB_USERNAME}/devops-tutorial:${IMAGE_TAG}"

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --remove-orphans --force-recreate

echo "Waiting for health status..."
for _ in {1..20}; do
  STATUS="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' devops-tutorial-app 2>/dev/null || true)"
  if [[ "$STATUS" == "healthy" ]]; then
    echo "Deployment successful."
    exit 0
  fi
  sleep 3
done

echo "Container did not become healthy in time."
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps
exit 1
