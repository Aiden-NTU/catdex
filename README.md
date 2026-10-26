# Catdex

Pokemon Go for cats — scan a real cat, roll a star card in a geofenced cell,
collect it, and battle.

Wave 0 engineering and product baselines:

- [v1 game design and formulas](docs/game-design.md)
- [architecture and trust boundaries](docs/architecture.md)
- [security checklist](docs/security-checklist.md)
- [privacy and OpenStreetMap prerequisites](docs/privacy.md)
- [release checklist](docs/release-checklist.md)

## Loop

1. **Map** — see your GPS cell (~500 m grid) and neighborhood
2. **Scan** — on-device TFLite detect + Oxford-12 breed (~91.7%) + 128-d identity
3. **Card** — deterministic ★1–5 from embedding × cell; stats scaled by stars
4. **Battle** — turn-based local PvP (ghost rival or another card)

Desktop builds bypass the geo enroll gate so you can demo without walking.

## Run

```bash
export PATH="/usr/bin:$HOME/sdks/flutter/bin:$PATH"
cd ~/Projects/catdex
flutter pub get
flutter run -d linux    # or your phone
```

On Linux, use **Pick photo** / demo cat if the camera plugin is unavailable.
Empty bag? Tap **Load demo pack** on Cards or Battle to seed four star cards.

On mobile, Catdex requests camera access for scanning and foreground location
for the coarse gameplay cell and nearby map. Photo-library access is requested
only when the player chooses an image. Denying a permission must not grant the
associated capability.

The map uses OpenStreetMap standard tiles. Any distributed build must visibly
show `© OpenStreetMap contributors` with a link to
<https://www.openstreetmap.org/copyright> and comply with the tile usage policy.
This attribution is a release gate; see the privacy baseline.

### Linux TFLite native lib

`tflite_flutter` needs `blobs/libtensorflowlite_c-linux.so` next to the binary.
Android/iOS ship this automatically; desktop does not. Until that `.so` is present,
Scan shows a model-load error but Map / Cards / Battle still work.

## Optional Nakama

Local bag sync hits `127.0.0.1:7350` when up; otherwise mirrors to SharedPreferences.

```bash
docker compose -f nakama/docker-compose.yml up -d
curl http://127.0.0.1:7350/healthcheck
```

## Models

Bundled under `assets/models/` (SSD detect + Oxford MobileNetV2 breed). See
[ml/README.md](ml/README.md).

## Tests

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build linux --release
flutter build apk --debug
```

CI also builds an iOS simulator target on macOS, scans the reachable Git history
for secrets, and validates the Nakama Docker Compose model.
