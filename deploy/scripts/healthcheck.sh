#!/bin/sh
set -eu

DEPLOY_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$DEPLOY_DIR"

set -a
# shellcheck disable=SC1091
. ./.env
set +a

URL="https://${CATDEX_DOMAIN}/healthcheck"
curl --fail --silent --show-error --max-time 10 "$URL" >/dev/null
docker compose --env-file .env -f compose.prod.yml exec -T postgres \
  pg_isready -U nakama -d nakama >/dev/null
docker compose --env-file .env -f compose.prod.yml exec -T prometheus \
  wget -q -O /dev/null http://127.0.0.1:9090/-/ready
docker compose --env-file .env -f compose.prod.yml exec -T loki \
  wget -q -O /dev/null http://127.0.0.1:3100/ready
printf 'Healthy: %s\n' "$URL"
