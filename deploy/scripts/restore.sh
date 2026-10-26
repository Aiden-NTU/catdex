#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: RESTORE_CONFIRM=restore-nakama $0 /path/to/backup.dump" >&2
  exit 2
fi
if [ "${RESTORE_CONFIRM:-}" != "restore-nakama" ]; then
  echo "Refusing destructive restore; set RESTORE_CONFIRM=restore-nakama" >&2
  exit 2
fi

DEPLOY_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BACKUP=$(realpath "$1")
test -r "$BACKUP"
if [ -f "$BACKUP.sha256" ]; then
  (cd "$(dirname "$BACKUP")" && sha256sum -c "$(basename "$BACKUP").sha256")
fi

cd "$DEPLOY_DIR"
docker compose --env-file .env -f compose.prod.yml stop nakama
trap 'docker compose --env-file .env -f compose.prod.yml start nakama >/dev/null 2>&1 || true' EXIT
docker compose --env-file .env -f compose.prod.yml exec -T postgres \
  psql -U nakama -d postgres -v ON_ERROR_STOP=1 \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='nakama' AND pid<>pg_backend_pid();" \
  -c "DROP DATABASE IF EXISTS nakama;" \
  -c "CREATE DATABASE nakama OWNER nakama;"
docker compose --env-file .env -f compose.prod.yml exec -T postgres \
  pg_restore -U nakama -d nakama --clean --if-exists --no-owner <"$BACKUP"
docker compose --env-file .env -f compose.prod.yml start nakama
trap - EXIT
echo "Restore complete; run scripts/healthcheck.sh"
