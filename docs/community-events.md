# Community events

Wave 4 events are server-authoritative, neighborhood-scale activities. The
client requests only its resolution-9 H3 cell and immediate ring; exact user
coordinates are used transiently for contribution eligibility and are never
stored in the contribution ledger.

## Templates

- **Cat Café Rally** debits one treat per accepted feed contribution.
- **Cardboard Fortress** requires a non-empty squad identifier.
- **Laser Pointer Chase** requires a configured checkpoint. Every seeded chase
  includes a stationary checkpoint so players do not have to walk a route.

Every event has an active time window, radius, goal, per-user cap, personal
reward, and community completion reward. The runtime serializes updates in a
database transaction, clips contributions to all caps, and records request IDs
for idempotent retries. Ended events remain visible for 24 hours and
`catdex_event_summary` reports the community outcome and personal contribution.

## Location and refresh behavior

The map asks for a foreground fix at launch or when the player explicitly
retries. It does not register a background or continuous location stream.
The accuracy halo displays device uncertainty, and the server allows that
uncertainty at the edge of an event radius while rejecting fixes over 250 m.
The map shows the H3 neighborhood, an animated pointer, available heading,
manual follow/recenter state, and OpenStreetMap attribution.

## Seeding

For production or staging, set `EVENT_H3_CELL`, `EVENT_LAT`, and `EVENT_LNG`,
then run:

```sh
EVENT_H3_CELL=89194ad... EVENT_LAT=51.5074 EVENT_LNG=-0.1278 \
  deploy/scripts/seed-events.sh
```

Optional `EVENT_STARTS_AT` and `EVENT_DURATION` schedule a future window. For
isolated development runtimes, setting `CATDEX_SEED_DEVELOPMENT_EVENTS=true`
before Nakama starts inserts the same three fixtures near
`CATDEX_EVENT_SEED_LAT`/`CATDEX_EVENT_SEED_LNG` (London defaults).

## Verification

`go test ./runtime` includes a 100-contributor simultaneous reference test,
replayed idempotency keys, cap invariants, and template eligibility. The Flutter
live test calls the real Nakama event RPC when a development fixture is present.
