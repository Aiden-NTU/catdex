# Authoritative geo enrollment

Catdex uses H3 resolution 9 on both Flutter (`h3_core`) and Nakama
(`uber/h3-go/v4`). The client sends its H3 cell plus latitude, longitude,
accuracy in meters, and the fix capture time. Nakama recomputes the cell and
rejects a mismatch.

Server defaults:

- maximum fix accuracy: 100 m
- maximum fix age: 120 seconds (with 30 seconds of future-clock tolerance)
- per-user, per-cell cooldown: 15 minutes
- daily enrollments per user: 25
- impossible-travel threshold: 300 km/h

The thresholds are configurable with `CATDEX_MAX_ENROLLMENT_ACCURACY_M`,
`CATDEX_MAX_ENROLLMENT_STALENESS_SECONDS`,
`CATDEX_ENROLLMENT_COOLDOWN_SECONDS`, `CATDEX_MAX_DAILY_ENROLLMENTS`, and
`CATDEX_IMPOSSIBLE_TRAVEL_KMH`. Speeds above half the travel threshold and fixes
in the least-accurate accepted quartile are retained as audit flags.

Request IDs are checked before freshness and geo validation so an exact queued
replay returns its original authoritative response. New requests still undergo
all current checks.

## Desktop development

PC simulation is opt-in at compile time:

```bash
flutter run -d linux \
  --dart-define=CATDEX_DEVELOPMENT_MODE=true \
  --dart-define=CATDEX_SIMULATED_LAT=51.5074 \
  --dart-define=CATDEX_SIMULATED_LNG=-0.1278
```

The map labels simulated fixes. Without development mode, location failures are
reported and never replaced with demo coordinates. Release builds disable both
simulation and the legacy desktop geo/identity bypass even if a development
define is accidentally supplied.
