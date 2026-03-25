#!/usr/bin/env bash
set -euo pipefail

API_BASE="${DOCKERHUB_API_BASE:-https://hub.docker.com/v2}"
USERNAME="${DOCKERHUB_USERNAME:-}"
REPOSITORY="${DOCKERHUB_REPOSITORY:-}"
DELETE_TOKEN="${DOCKERHUB_DELETE_TOKEN:-}"
KEEP_SHA_TAGS="${KEEP_SHA_TAGS:-10}"
PROTECTED_TAGS="${PROTECTED_TAGS:-}"
DRY_RUN="${DRY_RUN:-false}"

if [[ -z "$USERNAME" ]]; then
  echo "DOCKERHUB_USERNAME is required."
  exit 1
fi

if [[ -z "$REPOSITORY" ]]; then
  echo "DOCKERHUB_REPOSITORY is required."
  exit 1
fi

if [[ -z "$DELETE_TOKEN" ]]; then
  echo "DOCKERHUB_DELETE_TOKEN is required."
  exit 1
fi

if ! [[ "$KEEP_SHA_TAGS" =~ ^[0-9]+$ ]]; then
  echo "KEEP_SHA_TAGS must be a non-negative integer."
  exit 1
fi

if [[ "$DRY_RUN" != "true" && "$DRY_RUN" != "false" ]]; then
  echo "DRY_RUN must be true or false."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required."
  exit 1
fi

echo "Authenticating to Docker Hub API for ${USERNAME}/${REPOSITORY}"

auth_payload="$(jq -nc --arg username "$USERNAME" --arg password "$DELETE_TOKEN" '{username: $username, password: $password}')"
auth_response="$(
  curl -fsS \
    -H "Content-Type: application/json" \
    -X POST \
    -d "$auth_payload" \
    "${API_BASE}/users/login"
)"

bearer_token="$(echo "$auth_response" | jq -r '.token // .access_token // .jwt // empty')"

if [[ -z "$bearer_token" ]]; then
  echo "Failed to obtain Docker Hub API bearer token."
  exit 1
fi

tags_file="$(mktemp)"
delete_response_file="$(mktemp)"
trap 'rm -f "$tags_file" "$delete_response_file"' EXIT

next_url="${API_BASE}/namespaces/${USERNAME}/repositories/${REPOSITORY}/tags?page_size=100"

while [[ -n "$next_url" ]]; do
  page_response="$(
    curl -fsS \
      -H "Authorization: Bearer ${bearer_token}" \
      "$next_url"
  )"

  echo "$page_response" | jq -c '.results[] | {name, last_updated}' >> "$tags_file"
  next_url="$(echo "$page_response" | jq -r '.next // empty')"
done

total_tags="$(wc -l < "$tags_file" | tr -d ' ')"
echo "Fetched ${total_tags} tags from Docker Hub."

protected_tags_json="$(
  printf '%s' "$PROTECTED_TAGS" \
    | tr ',[:space:]' '\n' \
    | sed '/^$/d' \
    | jq -Rsc 'split("\n") | map(select(length > 0))'
)"

cleanup_candidates="$(
  jq -rs --argjson keep "$KEEP_SHA_TAGS" --argjson protected "$protected_tags_json" '
    map(select(.name | test("^sha-[0-9a-fA-F]{7,64}$")))
    | map(select(.name as $name | ($protected | index($name) | not)))
    | sort_by(.last_updated)
    | reverse
    | .[$keep:]
  ' "$tags_file"
)"

candidate_count="$(echo "$cleanup_candidates" | jq 'length')"

if [[ "$candidate_count" -eq 0 ]]; then
  echo "No stale sha-* tags to delete. keep=${KEEP_SHA_TAGS}"
  exit 0
fi

echo "Protected tags: ${PROTECTED_TAGS:-<none>}"
echo "Preparing to remove ${candidate_count} stale sha-* tags. keep=${KEEP_SHA_TAGS} dry_run=${DRY_RUN}"
echo "$cleanup_candidates" | jq -r '.[].name' | sed 's/^/ - /'

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry run enabled. No tags were deleted."
  exit 0
fi

while IFS= read -r tag_name; do
  [[ -z "$tag_name" ]] && continue

  delete_url="${API_BASE}/namespaces/${USERNAME}/repositories/${REPOSITORY}/tags/${tag_name}"
  http_code="$(
    curl -sS -o "$delete_response_file" -w "%{http_code}" \
      -H "Authorization: Bearer ${bearer_token}" \
      -X DELETE \
      "$delete_url"
  )"

  if [[ "$http_code" != "200" && "$http_code" != "202" && "$http_code" != "204" ]]; then
    echo "Failed to delete tag ${tag_name}. HTTP ${http_code}"
    cat "$delete_response_file"
    exit 1
  fi

  echo "Deleted ${tag_name}"
done < <(echo "$cleanup_candidates" | jq -r '.[].name')

echo "Docker Hub cleanup completed."
