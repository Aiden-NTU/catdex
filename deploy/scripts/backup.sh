#!/bin/sh
set -eu

DEPLOY_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BACKUP_DIR=${BACKUP_DIR:-"$DEPLOY_DIR/backups"}
RETENTION_DAYS=${RETENTION_DAYS:-14}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$BACKUP_DIR/nakama-$STAMP.dump"

mkdir -p "$BACKUP_DIR"
cd "$DEPLOY_DIR"
umask 077
docker compose --env-file .env -f compose.prod.yml exec -T postgres \
  pg_dump -U nakama -d nakama --format=custom --compress=9 >"$OUT"
test -s "$OUT"
sha256sum "$OUT" >"$OUT.sha256"
find "$BACKUP_DIR" -type f -name 'nakama-*.dump*' -mtime +"$RETENTION_DAYS" -delete
printf 'Backup written: %s\n' "$OUT"
