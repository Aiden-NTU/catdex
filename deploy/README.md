# Catdex Nakama operations

This stack runs Nakama/PostgreSQL behind Caddy TLS and keeps Prometheus, Loki,
and Grafana on private Docker networks. Grafana binds to loopback only; use an
SSH tunnel for access. The Nakama console is intentionally not exposed.

## First deployment

Requirements: Docker Engine with Compose v2, DNS for the API host, and inbound
TCP 80/443 plus UDP 443. Do not expose PostgreSQL, Nakama, Prometheus, or Loki.

```sh
cd deploy
cp .env.example .env
chmod 600 .env
# Replace every placeholder. Generate independent values, for example:
openssl rand -base64 48
docker compose --env-file .env -f compose.prod.yml config
docker compose --env-file .env -f compose.prod.yml build
docker compose --env-file .env -f compose.prod.yml up -d
./scripts/healthcheck.sh
```

Production has no default credentials or `defaultkey`: Compose refuses to
start when required variables are absent. Keep `.env` outside backups and
restrict it to the deployment operator.

Clients should authenticate with Nakama (device, email, or another configured
provider), then call RPCs with the returned session bearer token. Protected
RPCs ignore any payload `userId` and derive ownership from the session.

## Runtime RPCs

- `catdex_health`: public runtime/database probe.
- `catdex_bootstrap`: identity, feature flags, and inventory count.
- `catdex_get_inventory`, `catdex_upsert_inventory`: the authenticated bag.
- `catdex_enroll`: idempotent enrollment, per-user cooldown, duplicate
  fingerprint/day protection, and server-secret deterministic stars/stats.
- `catdex_feed`: idempotent XP ledger and levels (1-100).
- `catdex_nearby_events`, `catdex_contribute_event`: active-cell events and
  transactional capped contributions.
- `catdex_get_opponent`: finds another user's server-stored card.
- `catdex_resolve_battle`: idempotent deterministic server simulation using
  only stored fighter stats; updates both cards' win/loss totals.

All mutating calls require a unique `requestId` (UUIDs are recommended).
Enrollment accepts a stable, non-biometric identity fingerprint; the server
stores only its SHA-256 digest. H3 cells are treated as opaque cell IDs.
Create scheduled events through an audited operator SQL migration or admin
job; there is deliberately no client event-creation RPC.

## Routine operations

```sh
# Logs and status
docker compose --env-file .env -f compose.prod.yml ps
docker compose --env-file .env -f compose.prod.yml logs --since=30m nakama caddy

# Upgrade after reviewing image/runtime release notes
docker compose --env-file .env -f compose.prod.yml build --pull nakama
docker compose --env-file .env -f compose.prod.yml pull
docker compose --env-file .env -f compose.prod.yml up -d

# Grafana through an SSH tunnel
ssh -L 3000:127.0.0.1:3000 user@server
```

Alert externally on failed HTTPS health checks, PostgreSQL disk pressure,
container restarts, elevated RPC errors/latency, and backup age. The supplied
single-node Loki and PostgreSQL setup is appropriate for one host; use managed
PostgreSQL/object storage and multiple Nakama nodes when host-level HA is
required.

## Backups and disaster recovery

Run `scripts/backup.sh` from cron/systemd daily. It writes mode-restricted,
checksummed PostgreSQL custom dumps under `deploy/backups`; copy them to
encrypted off-host storage. `RETENTION_DAYS` defaults to 14.

Test restores regularly on a non-production host:

```sh
RESTORE_CONFIRM=restore-nakama ./scripts/restore.sh backups/nakama-TIMESTAMP.dump
./scripts/healthcheck.sh
```

Restore is destructive and briefly stops Nakama. Snapshot Caddy/Grafana data
only if their local state matters; gameplay authority is in PostgreSQL.

## Security notes

Rotate Nakama and database secrets during a maintenance window. Changing
session encryption keys invalidates sessions. Rotate `CATDEX_ENROLLMENT_SECRET`
only with care because it changes future deterministic star allocation.
Terminate operator access through SSH/VPN, patch the host and images, and
enable a firewall. Promtail reads container log files without Docker API access.
