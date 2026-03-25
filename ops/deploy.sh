#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_ENV="${DEPLOY_ENV:-production}"
COMPOSE_FILE="$ROOT_DIR/docker-compose.${DEPLOY_ENV}.yml"
ENV_FILE="$ROOT_DIR/ops/.env.${DEPLOY_ENV}"
LOCK_FILE="/tmp/devops-tutorial-deploy-${DEPLOY_ENV}.lock"
CONTAINER_NAME="devops-tutorial-${DEPLOY_ENV}-app"
COMPOSE_PROJECT_NAME="devops-tutorial-${DEPLOY_ENV}"

case "$DEPLOY_ENV" in
  dev|staging|production)
    ;;
  *)
    echo "Unsupported DEPLOY_ENV: $DEPLOY_ENV"
    echo "Expected one of: dev, staging, production"
    exit 1
    ;;
esac

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  echo "Copy ops/.env.${DEPLOY_ENV}.example to ops/.env.${DEPLOY_ENV} and update values."
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

IMAGE_TAG="${IMAGE_TAG:-}"
if [[ -z "$IMAGE_TAG" ]]; then
  if [[ "$DEPLOY_ENV" == "dev" || "$DEPLOY_ENV" == "staging" ]]; then
    IMAGE_TAG="latest"
  else
    echo "IMAGE_TAG is required in $ENV_FILE for production deployments."
    exit 1
  fi
fi

if [[ "$DEPLOY_ENV" == "production" ]]; then
  if [[ ! "$IMAGE_TAG" =~ ^sha-[0-9a-fA-F]{7,64}$ && ! "$IMAGE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Production deployments only accept sha-* or vX.Y.Z image tags."
    exit 1
  fi
fi

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
    STATUS="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' "$CONTAINER_NAME" 2>/dev/null || true)"
    if [[ "$STATUS" == "healthy" ]]; then
      return 0
    fi
    sleep 3
  done

  return 1
}

if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  CURRENT_IMAGE="$(docker inspect --format='{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || true)"
  if [[ -n "$CURRENT_IMAGE" && "$CURRENT_IMAGE" == *:* ]]; then
    CURRENT_IMAGE_TAG="${CURRENT_IMAGE##*:}"
  fi
fi

echo "Deploying ${DEPLOY_ENV} with docker.io/${DOCKERHUB_USERNAME}/devops-tutorial:${IMAGE_TAG}"
if [[ -n "$CURRENT_IMAGE_TAG" ]]; then
  echo "Current running tag: ${CURRENT_IMAGE_TAG}"
fi

COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull

COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --remove-orphans --force-recreate

if wait_for_healthy; then
  echo "Deployment successful."
  exit 0
fi

echo "Container did not become healthy in time."
COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps

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

COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" pull
COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --remove-orphans --force-recreate

if wait_for_healthy; then
  echo "Rollback successful. Service restored with tag ${CURRENT_IMAGE_TAG}."
else
  echo "Rollback failed. Service may be unavailable."
  COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps
fi

exit 1
