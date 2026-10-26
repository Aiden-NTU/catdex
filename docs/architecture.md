# Architecture baseline

## System boundaries

- **Flutter client:** UI, camera/photo input, location gating, local SQLite and
  preferences, on-device TFLite inference, deterministic card presentation, and
  an offline-capable battle demo.
- **Nakama:** optional v1 identity/session, authoritative inventory and economy,
  idempotent synchronization, event configuration, and future authoritative
  online battles.
- **PostgreSQL:** Nakama-owned durable state. It is not exposed to clients.
- **Third parties:** OpenStreetMap standard raster tiles and platform location,
  camera, and photo-picker APIs.

The repository's `nakama/docker-compose.yml` is local development
infrastructure, not a production deployment.

## Data flow

1. The OS grants foreground camera or photo access and foreground location.
2. TFLite models process the image locally. Raw images and embeddings do not
   leave the device by default.
3. The client derives an H3 resolution-9 cell for display and submits the
   location fix (latitude/longitude, accuracy, and capture time) for enrollment.
4. Nakama recomputes H3 with Uber H3 v4 and rejects mismatches, stale or
   inaccurate fixes, per-cell cooldown violations, daily-cap violations, and
   impossible travel. Accepted cards and star rolls are server-authoritative.
5. Enrollment retries use a stable request ID. Offline requests remain visibly
   queued until the authoritative card is returned; local state cannot approve
   production enrollment.
6. Map views request OSM tiles directly over HTTPS and display attribution.

## Trust boundaries

The device and all client-calculated outcomes are untrusted. Production
inventory, event eligibility, rewards, balances, cooldowns, and online battle
outcomes must be validated server-side. PostgreSQL accepts traffic only from
Nakama. Administrative APIs and secrets must never ship in the app.

## Offline and failure behavior

- Scanning and local battles may continue without Nakama.
- Pending mutations have a stable UUID, creation time, rules version, and
  payload hash. Replays are safe and server deduplication is mandatory.
- Conflicts resolve to server-authoritative inventory and balances. Local-only
  records remain visibly pending or rejected; they are not silently discarded.
- Missing ML models disable scanning with an actionable error, while collection
  browsing and battles remain available.
- A tile/network failure leaves gameplay controls usable and must not trigger
  repeated aggressive retries.

## Versioning and observability

Enrollment location and audit flags are retained with the enrollment ledger for
abuse review; production must define a minimization/deletion period. Persist
schema, game-rules, model, and API versions with generated records.
Breaking protocol changes require a migration and a minimum supported client
version. Logs use request IDs and pseudonymous account IDs; never log tokens,
photos, embeddings, exact coordinates, or user-entered names.

## Architecture review checklist

- [ ] A data-flow or trust-boundary change is documented.
- [ ] New state has ownership, migration, retention, and deletion behavior.
- [ ] Offline retries are idempotent and conflict behavior is tested.
- [ ] Client claims are validated at the authoritative boundary.
- [ ] Network calls use TLS, timeouts, bounded retries, and safe fallbacks.
- [ ] Third-party terms, attribution, capacity, and privacy impact are reviewed.
- [ ] API and game-rule compatibility is explicit.
- [ ] Operational health, structured errors, and redaction are covered.
