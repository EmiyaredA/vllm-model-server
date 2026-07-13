#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8000}"
BASE_URL="http://${HOST}:${PORT}"

if [[ -n "${API_KEY:-}" ]]; then
  AUTH_HEADER=(-H "Authorization: Bearer ${API_KEY}")
else
  AUTH_HEADER=()
fi

echo "Checking health: ${BASE_URL}/health"
curl -fsS "${AUTH_HEADER[@]}" "${BASE_URL}/health"
echo

echo "Listing models: ${BASE_URL}/v1/models"
curl -fsS "${AUTH_HEADER[@]}" "${BASE_URL}/v1/models"
echo

echo "OK"
