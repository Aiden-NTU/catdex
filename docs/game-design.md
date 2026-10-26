# Catdex v1 game design

This document is the balancing contract for v1. Constants may be tuned, but
clients and servers must use the same versioned rules. The current prototype
implements collection, deterministic star rolls, and local battles; progression,
currency, and scheduled events below define the v1 target.

## Core loop and guardrails

1. Discover a roughly 500 m map cell.
2. Scan a cat on-device or explicitly choose a photo.
3. Pass quality and duplicate checks, then mint one card.
4. Battle to earn account XP and soft currency.
5. Revisit after the cell cooldown or during an event.

The camera image and ML embedding stay on-device by default. A player must not
photograph people or enter private property. Location is used only while the app
is in use. One successful collection per cell is allowed every 15 minutes.

## Card generation

The roll seed is:

`SHA-256(cell_id + "|" + UTC_calendar_day + "|" + embedding_bytes)`

The resulting deterministic uniform value `r` selects stars:

| Stars | Range | Probability |
| --- | --- | --- |
| 1 | `0.00 <= r < 0.40` | 40% |
| 2 | `0.40 <= r < 0.70` | 30% |
| 3 | `0.70 <= r < 0.88` | 18% |
| 4 | `0.88 <= r < 0.97` | 9% |
| 5 | `0.97 <= r < 1.00` | 3% |

For each base stat `s`:

`star_multiplier = 1 + 0.12 * (stars - 1)`

`final_stat = clamp(round(s * star_multiplier), 1, 150)`

`battle_power = attack + defense + speed`

The same embedding, cell, and UTC day therefore produces the same rarity. The
server must recompute and validate a synced card rather than trust client stats.

## Account progression

Levels run from 1 through 40. XP is cumulative and never spent.

`xp_to_next(level) = 100 * level^2`, for levels 1–39

`total_xp_for_level(L) = 100 * (L - 1) * L * (2L - 1) / 6`

XP awards:

- Valid first collection of a distinct cat identity: 100 XP.
- Re-encounter rejected as a duplicate: 0 XP.
- Battle win: 60 XP; battle loss: 25 XP; draw: 35 XP.
- First battle win of a UTC day: +40 XP.
- Event XP uses `floor(base_xp * event_xp_multiplier)`; bonuses are then added.

Unlocks: battle at level 2, events at level 3, and ranked matchmaking at level
5. No card stat scales with account level.

## Economy

The sole v1 currency is **Paw Coins**, an earn-only soft currency. There is no
paid currency, trading, staking, loot-box purchase, or cash-out.

- New distinct collection: 10 coins.
- Battle win/loss/draw: 8/3/5 coins.
- First win of the day: +5 coins.
- Daily earn cap: 100 coins, reset at 00:00 UTC. Rewards above the cap grant XP
  but no coins.
- Cosmetic profile frame: 250 coins.
- Collection capacity +25 slots: 500 coins, up to four purchases.

Balances and purchases are server-authoritative when signed in. Offline rewards
are queued with an idempotency key and reconciled on sync. A rejected operation
must not consume or grant currency.

## Cat care and progression

Cat progression is server-owned and separate from account progression. Cat
levels run from 1 through 40 using cumulative XP and
`xp_to_next(level) = 100 * level^2`. Care never decays meters while the player
is away: there is no neglect penalty.

Care meters and resources are bounded:

- Energy, full tummy, mood, bond, and ability mastery stay within 0–100.
- Feed uses one treat (30-minute cooldown): +15 XP, up to +2 coins.
- Play costs 15 energy (20-minute cooldown): +20 XP, up to +3 coins.
- Groom uses one grooming supply (4-hour cooldown): +20 XP, up to +3 coins.
- Train costs 20 energy (1-hour cooldown): +30 XP, up to +4 coins.
- Rest restores energy (15-minute cooldown) and grants no XP or coins.

The account starts with five treats and three grooming supplies. On each new
UTC day it receives up to three treats (inventory cap 20) and one grooming
supply (cap 10). Care coin awards share the 100 Paw Coin daily earn cap.
Every mutation has an idempotency key and an append-only ledger entry.

Battle stats are recalculated by the server from immutable enrolled base stats,
cat level, and ability mastery. Clients cache the result but cannot author it.

## Battle rules

Each fighter starts at 100 HP. Higher speed acts first; ties favor the initially
listed fighter. A match ends on knockout or after 12 rounds; at timeout, higher
remaining HP wins (the initially listed fighter wins an exact tie).

For attack or ability multiplier `m`:

`raw_damage = attack * m - defender_defense * 0.35`

`damage = clamp(round(raw_damage), 4, 40)`

If defending, `damage = clamp(round(damage * 0.55), 2, 40)`.

Critical chance is `0.08 + 0.01 * stars`; a critical applies
`round(damage * 1.5)` after defense and may exceed 40. A normal attack uses
`m = 1`. A once-per-battle ability uses a uniformly sampled multiplier in
`[1.35, 1.60)`. All random choices derive from the match seed. A production
online match is server-authoritative; clients submit actions, not outcomes.

## Events

An event is a signed, server-supplied rule set with `id`, UTC start/end,
eligible cells, and bounded multipliers. Clients fall back to normal rules if
the document is absent, invalid, expired, or from the future.

Allowed v1 formulas:

- `event_xp = floor(base_xp * xp_multiplier)`, where `1.0 <= multiplier <= 2.0`.
- `event_coins = floor(base_coins * coin_multiplier)`, where
  `1.0 <= multiplier <= 1.5`; the daily cap still applies.
- Rarity weighting uses `w'_s = w_s * rarity_multiplier_s`, each multiplier in
  `[0.5, 2.0]`, then `P(s) = w'_s / sum(w')`. The deterministic hash selects
  from this cumulative distribution.

Events may change rewards and rarity weights, but never battle stats for cards
already minted. Event identifiers and rule versions must be retained in reward
and card audit records.

## Balance telemetry

Track only pseudonymous, consented aggregates: collection success/failure
reason, star distribution, battle duration/outcome, rewards, and progression
level. Do not collect photos, raw embeddings, exact location trails, or free-form
cat names as analytics. Review rarity distribution, battle win rate by star
difference, inflation, and progression time before every balance change.
