# Release checklist

## Scope and quality

- [ ] Version, build number, rules version, model version, and release notes are set.
- [ ] Flutter formatting, analysis, unit/widget tests, and Linux build pass.
- [ ] Android release APK/app bundle and unsigned iOS build pass.
- [ ] Camera, photo picker, foreground location, denial, and settings-return
      flows are tested on supported physical Android and iOS devices.
- [ ] Production enrollment rejects H3 mismatch, stale/inaccurate fixes,
      impossible travel, per-cell cooldown, and daily-cap violations.
- [ ] Release builds cannot enable simulated location or geo/identity bypasses.
- [ ] Offline launch, pending sync, duplicate retry, conflict, and recovery pass.
- [ ] Battle seeds reproduce outcomes and reward requests are idempotent.
- [ ] Accessibility labels, text scaling, contrast, and reduced motion are checked.

## Privacy, security, and stores

- [ ] Security and privacy checklists are complete with named owners.
- [ ] Secret scan, dependency review, and container/config validation pass.
- [ ] Android permissions and iOS purpose strings match actual functionality.
- [ ] Privacy notice, terms, support URL, account deletion, store labels, and age
      rating are ready.
- [ ] OSM attribution is visible; tile-provider usage and expected capacity are approved.
- [ ] Signing happens only in the protected release environment.
- [ ] Production endpoints use TLS and no debug/admin credentials ship.

## Operations and rollout

- [ ] Database migration, backup, restore, and rollback are rehearsed.
- [ ] Dashboards cover errors, latency, sync rejection, economy anomalies, and
      client/rules versions without sensitive payloads.
- [ ] Rate limits, daily reward caps, event bounds, and abuse alerts are enabled.
- [ ] Event start/end and timezone behavior are tested against UTC.
- [ ] Support, privacy, security, and incident owners are on call.
- [ ] Staged rollout and halt thresholds are recorded.
- [ ] Previous compatible build/config remains available for rollback.

## Sign-off

Record release version, commit, artifacts/checksums, environment, approvers,
known risks, rollout percentage, and rollback decision in the release record.
