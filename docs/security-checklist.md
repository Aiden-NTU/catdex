# Security baseline and checklist

## Baseline

Treat the mobile client, local database, generated card stats, device clock, and
location as attacker-controlled. Production rewards and shared state require an
authenticated, rate-limited, server-authoritative decision. Use TLS in transit
and platform-protected storage for refresh tokens. Never put service credentials,
database passwords, signing keys, or administrative Nakama keys in the app or
repository.

Images and embeddings are biometric-adjacent data even when they identify cats,
so they remain on-device by default and must not appear in logs or crash reports.
Exact coordinates are sensitive location data.

## Pull request checklist

- [ ] Inputs are length-, type-, and range-validated at their trust boundary.
- [ ] Authorization checks object ownership, not only authentication.
- [ ] Economy, cooldown, event, and battle mutations are server-authoritative
      and idempotent.
- [ ] Randomness used for shared outcomes is server-generated or verifiable.
- [ ] Tokens use secure platform storage and are redacted from logs/errors.
- [ ] No secret, private key, production endpoint credential, or real user data
      is committed; CI secret scanning passes.
- [ ] Dependencies and container actions are pinned and reviewed.
- [ ] Network operations use HTTPS, timeouts, bounded retries, and no permissive
      certificate bypass.
- [ ] SQL/command/template construction uses safe parameterization.
- [ ] New permissions are necessary, foreground-scoped where possible, and
      documented to users.
- [ ] Abuse controls cover replay, automation, impossible travel, reward caps,
      and request rate.
- [ ] Logs and analytics exclude images, embeddings, exact coordinates, names,
      tokens, and database payloads.
- [ ] Failure messages do not reveal credentials, internals, or other users.

## Release security gate

- [ ] Run Flutter analysis/tests and platform release builds.
- [ ] Validate Android manifest and iOS property list.
- [ ] Run secret scanning across the full reachable Git history.
- [ ] Review dependency advisories and image provenance.
- [ ] Use production secrets supplied by the deployment environment.
- [ ] Rotate any credential ever committed, even if later removed.
- [ ] Confirm least-privilege database/network access and encrypted backups.
- [ ] Exercise account deletion, token revocation, restore, and incident rollback.
- [ ] Record an owner for vulnerability intake and incident response.
