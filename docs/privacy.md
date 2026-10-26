# Privacy baseline

This is an engineering baseline, not a substitute for a jurisdiction-specific
privacy notice. Before public distribution, publish an accessible notice and
store-listing disclosures that match actual behavior.

## Data inventory and purpose

| Data | Purpose | Default handling |
| --- | --- | --- |
| Camera frame or chosen photo | Detect/classify a cat | Process on-device; do not upload or retain by default |
| Cat embedding | Duplicate detection and deterministic roll | Keep on-device; never analytics |
| Foreground location | Determine coarse gameplay cell and center map | Request only while in use; avoid exact-location history |
| Cat card and coarse cell ID | Collection and optional sync | Local; sync only when enabled/signed in |
| Account/session identifiers | Authentication and abuse prevention | Server when online; tokens in protected device storage |
| Gameplay events | Balance and reliability | Pseudonymous, minimized, consented where required |
| OSM tile request metadata | Render the map | Sent directly to the configured tile provider |

Do not intentionally collect human faces, contact lists, advertising IDs, or
background location. A user choosing an image remains responsible for having
permission to use it.

## OpenStreetMap prerequisites

The current map uses `https://tile.openstreetmap.org`. Before release:

- Show visible `© OpenStreetMap contributors` attribution linked to
  `https://www.openstreetmap.org/copyright`.
- Follow the OSM Foundation tile usage policy. Set an identifiable application
  user agent where the platform stack permits, cache normally, avoid bulk
  download/prefetch, and never bypass provider controls.
- Disclose that the tile host receives IP address, user agent, requested tile
  coordinates (which approximate the viewed area), and request time.
- For material traffic, use a suitable commercial/self-hosted provider with a
  capacity agreement; do not treat the community standard tile service as an
  unlimited production CDN.
- Re-review attribution, terms, retention, and international transfer details
  whenever the tile provider changes.

## User controls and lifecycle

- Explain permission purpose before the OS prompt. Denial leaves browsing and
  non-camera paths usable where practical.
- Provide access/export and deletion for server-held account and collection
  data. Deletion revokes sessions and enters backups under a documented expiry.
- Define retention before collection. Suggested baseline: operational security
  logs 30 days, aggregated non-identifying metrics longer, and pending offline
  mutations until sync/rejection or 30 days.
- Obtain opt-in consent where required for optional analytics and provide a
  persistent opt-out.
- Do not use collected data for model training without separate, explicit,
  revocable consent.

## Privacy review checklist

- [ ] Data inventory, purpose, recipient, retention, and lawful basis are current.
- [ ] Store privacy labels/data-safety forms match runtime and SDK behavior.
- [ ] Camera, photos, and foreground location have accurate purpose strings.
- [ ] Raw photos, embeddings, and exact location are absent from telemetry.
- [ ] Consent and permission denial paths are tested.
- [ ] Access, export, deletion, and analytics opt-out are tested.
- [ ] Child-safety/age requirements and regional launch scope are decided.
- [ ] OSM attribution is visible and tile-provider policy is satisfied.
- [ ] Third-party processors and cross-border transfers are documented.
- [ ] A contact and response process exists for privacy requests/incidents.
