package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"

	"github.com/heroiclabs/nakama-common/runtime"
)

var enrollmentSecret string

func InitModule(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, initializer runtime.Initializer) error {
	enrollmentSecret = os.Getenv("CATDEX_ENROLLMENT_SECRET")
	if len(enrollmentSecret) < 32 {
		return fmt.Errorf("CATDEX_ENROLLMENT_SECRET must be at least 32 characters")
	}
	if err := migrate(ctx, db); err != nil {
		return fmt.Errorf("catdex schema: %w", err)
	}
	if err := seedDevelopmentEvents(ctx, db); err != nil {
		return fmt.Errorf("catdex event seed: %w", err)
	}
	rpcs := map[string]func(context.Context, runtime.Logger, *sql.DB, runtime.NakamaModule, string) (string, error){
		"catdex_health":           rpcHealth,
		"catdex_bootstrap":        rpcBootstrap,
		"catdex_get_inventory":    rpcGetInventory,
		"catdex_upsert_inventory": rpcUpsertInventory,
		"catdex_enroll":           rpcEnroll,
		"catdex_feed":             rpcFeed,
		"catdex_get_care_state":   rpcGetCareState,
		"catdex_care_action":      rpcCareAction,
		"catdex_nearby_events":    rpcNearbyEvents,
		"catdex_contribute_event": rpcContributeEvent,
		"catdex_event_summary":    rpcEventSummary,
		"catdex_get_opponent":     rpcGetOpponent,
		"catdex_resolve_battle":   rpcResolveBattle,
		"catdex_battle_start":     rpcBattleStart,
		"catdex_battle_get":       rpcBattleGet,
		"catdex_battle_action":    rpcBattleAction,
		"catdex_account_export":   rpcAccountExport,
		"catdex_account_delete":   rpcAccountDelete,
		"catdex_admin_seed_event": rpcAdminSeedEvent,
		"catdex_admin_retention":  rpcAdminRetention,
	}
	for name, fn := range rpcs {
		if err := initializer.RegisterRpc(name, hardenRPC(name, fn)); err != nil {
			return fmt.Errorf("register %s: %w", name, err)
		}
	}
	logger.Info("Catdex runtime initialized with %d RPCs", len(rpcs))
	return nil
}

func migrate(ctx context.Context, db *sql.DB) error {
	const schema = `
CREATE TABLE IF NOT EXISTS catdex_inventory (
  user_id UUID NOT NULL, card_id TEXT NOT NULL, card JSONB NOT NULL,
  authoritative BOOLEAN NOT NULL DEFAULT false,
  level INT NOT NULL DEFAULT 1, xp INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, card_id)
);
ALTER TABLE catdex_inventory ADD COLUMN IF NOT EXISTS authoritative BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE catdex_inventory ADD COLUMN IF NOT EXISTS energy INT NOT NULL DEFAULT 100;
ALTER TABLE catdex_inventory ADD COLUMN IF NOT EXISTS hunger INT NOT NULL DEFAULT 100;
ALTER TABLE catdex_inventory ADD COLUMN IF NOT EXISTS mood INT NOT NULL DEFAULT 75;
ALTER TABLE catdex_inventory ADD COLUMN IF NOT EXISTS bond INT NOT NULL DEFAULT 0;
ALTER TABLE catdex_inventory ADD COLUMN IF NOT EXISTS ability_mastery INT NOT NULL DEFAULT 0;
ALTER TABLE catdex_inventory ADD COLUMN IF NOT EXISTS base_stats JSONB;
ALTER TABLE catdex_inventory ADD COLUMN IF NOT EXISTS last_fed_at TIMESTAMPTZ;
ALTER TABLE catdex_inventory ADD COLUMN IF NOT EXISTS last_played_at TIMESTAMPTZ;
ALTER TABLE catdex_inventory ADD COLUMN IF NOT EXISTS last_groomed_at TIMESTAMPTZ;
ALTER TABLE catdex_inventory ADD COLUMN IF NOT EXISTS last_trained_at TIMESTAMPTZ;
ALTER TABLE catdex_inventory ADD COLUMN IF NOT EXISTS last_rested_at TIMESTAMPTZ;
ALTER TABLE catdex_inventory ADD COLUMN IF NOT EXISTS progression_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
UPDATE catdex_inventory SET base_stats=card->'stats' WHERE base_stats IS NULL;
CREATE INDEX IF NOT EXISTS catdex_inventory_opponents ON catdex_inventory (user_id, updated_at DESC);
CREATE TABLE IF NOT EXISTS catdex_accounts (
  user_id UUID PRIMARY KEY, paw_coins INT NOT NULL DEFAULT 0,
  daily_earned INT NOT NULL DEFAULT 0, day_bucket DATE NOT NULL DEFAULT (now() AT TIME ZONE 'utc')::date,
  treats INT NOT NULL DEFAULT 5, grooming_supplies INT NOT NULL DEFAULT 3,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (paw_coins >= 0 AND daily_earned >= 0 AND treats >= 0 AND grooming_supplies >= 0)
);
CREATE TABLE IF NOT EXISTS catdex_economy_ledger (
  sequence BIGSERIAL PRIMARY KEY, user_id UUID NOT NULL, request_id TEXT NOT NULL,
  card_id TEXT, action TEXT NOT NULL, xp_delta INT NOT NULL DEFAULT 0,
  coin_delta INT NOT NULL DEFAULT 0, treats_delta INT NOT NULL DEFAULT 0,
  grooming_delta INT NOT NULL DEFAULT 0, response JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(user_id, request_id)
);
CREATE INDEX IF NOT EXISTS catdex_economy_ledger_user ON catdex_economy_ledger(user_id, sequence);
CREATE TABLE IF NOT EXISTS catdex_enrollments (
  user_id UUID NOT NULL, request_id TEXT NOT NULL, fingerprint TEXT NOT NULL,
  day_bucket DATE NOT NULL, card_id TEXT NOT NULL, response JSONB NOT NULL,
  h3_cell TEXT, lat DOUBLE PRECISION, lng DOUBLE PRECISION,
  accuracy_m DOUBLE PRECISION, captured_at TIMESTAMPTZ, audit_flags TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, request_id), UNIQUE (user_id, fingerprint, day_bucket)
);
ALTER TABLE catdex_enrollments ADD COLUMN IF NOT EXISTS h3_cell TEXT;
ALTER TABLE catdex_enrollments ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION;
ALTER TABLE catdex_enrollments ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION;
ALTER TABLE catdex_enrollments ADD COLUMN IF NOT EXISTS accuracy_m DOUBLE PRECISION;
ALTER TABLE catdex_enrollments ADD COLUMN IF NOT EXISTS captured_at TIMESTAMPTZ;
ALTER TABLE catdex_enrollments ADD COLUMN IF NOT EXISTS audit_flags TEXT[] NOT NULL DEFAULT '{}';
CREATE INDEX IF NOT EXISTS catdex_enrollments_cooldown ON catdex_enrollments (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS catdex_enrollments_cell_cooldown ON catdex_enrollments (user_id, h3_cell, created_at DESC);
CREATE INDEX IF NOT EXISTS catdex_enrollments_travel ON catdex_enrollments (user_id, captured_at DESC);
CREATE TABLE IF NOT EXISTS catdex_feed_ledger (
  user_id UUID NOT NULL, request_id TEXT NOT NULL, card_id TEXT NOT NULL,
  amount INT NOT NULL, xp_awarded INT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, request_id)
);
CREATE TABLE IF NOT EXISTS catdex_events (
  id UUID PRIMARY KEY, h3_cell TEXT NOT NULL, kind TEXT NOT NULL, title TEXT NOT NULL,
  goal INT NOT NULL CHECK (goal > 0), progress INT NOT NULL DEFAULT 0,
  starts_at TIMESTAMPTZ NOT NULL, ends_at TIMESTAMPTZ NOT NULL
);
ALTER TABLE catdex_events ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '';
ALTER TABLE catdex_events ADD COLUMN IF NOT EXISTS radius_m INT NOT NULL DEFAULT 500;
ALTER TABLE catdex_events ADD COLUMN IF NOT EXISTS per_user_cap INT NOT NULL DEFAULT 20;
ALTER TABLE catdex_events ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION NOT NULL DEFAULT 0;
ALTER TABLE catdex_events ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION NOT NULL DEFAULT 0;
ALTER TABLE catdex_events ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}';
ALTER TABLE catdex_events ADD COLUMN IF NOT EXISTS personal_reward INT NOT NULL DEFAULT 5;
ALTER TABLE catdex_events ADD COLUMN IF NOT EXISTS community_reward INT NOT NULL DEFAULT 20;
DO $$ BEGIN
  ALTER TABLE catdex_events ADD CONSTRAINT catdex_events_kind_check
    CHECK (kind IN ('cat_cafe_rally','cardboard_fortress','laser_pointer_chase')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE INDEX IF NOT EXISTS catdex_events_nearby ON catdex_events (h3_cell, ends_at);
CREATE TABLE IF NOT EXISTS catdex_event_contributions (
  event_id UUID NOT NULL REFERENCES catdex_events(id), user_id UUID NOT NULL,
  request_id TEXT NOT NULL, amount INT NOT NULL CHECK (amount > 0),
  contribution_type TEXT NOT NULL DEFAULT '', squad_id TEXT, checkpoint_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, request_id)
);
ALTER TABLE catdex_event_contributions ADD COLUMN IF NOT EXISTS contribution_type TEXT NOT NULL DEFAULT '';
ALTER TABLE catdex_event_contributions ADD COLUMN IF NOT EXISTS squad_id TEXT;
ALTER TABLE catdex_event_contributions ADD COLUMN IF NOT EXISTS checkpoint_id TEXT;
CREATE INDEX IF NOT EXISTS catdex_event_contributions_totals
  ON catdex_event_contributions(event_id,user_id);
CREATE TABLE IF NOT EXISTS catdex_event_rewards (
  event_id UUID NOT NULL REFERENCES catdex_events(id), user_id UUID NOT NULL,
  personal_reward INT NOT NULL DEFAULT 0, community_reward INT NOT NULL DEFAULT 0,
  claimed_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY(event_id,user_id)
);
CREATE TABLE IF NOT EXISTS catdex_battles (
  id UUID PRIMARY KEY, user_id UUID NOT NULL, request_id TEXT NOT NULL,
  opponent_user_id UUID NOT NULL, result JSONB NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, request_id)
);
CREATE TABLE IF NOT EXISTS catdex_battle_matches (
  id UUID PRIMARY KEY, creator_user_id UUID NOT NULL, request_id TEXT NOT NULL,
  player_a_user_id UUID NOT NULL, player_b_user_id UUID NOT NULL,
  state JSONB NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (creator_user_id, request_id)
);
CREATE INDEX IF NOT EXISTS catdex_battle_matches_player_a
  ON catdex_battle_matches(player_a_user_id,updated_at DESC);
CREATE INDEX IF NOT EXISTS catdex_battle_matches_player_b
  ON catdex_battle_matches(player_b_user_id,updated_at DESC);
CREATE TABLE IF NOT EXISTS catdex_battle_action_ids (
  match_id UUID NOT NULL REFERENCES catdex_battle_matches(id) ON DELETE CASCADE,
  request_id TEXT NOT NULL, response JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY(match_id,request_id)
);
CREATE TABLE IF NOT EXISTS catdex_rpc_rate_limits (
  subject TEXT NOT NULL, rpc TEXT NOT NULL, window_start TIMESTAMPTZ NOT NULL,
  hits INT NOT NULL CHECK (hits > 0), PRIMARY KEY(subject,rpc,window_start)
);
CREATE INDEX IF NOT EXISTS catdex_rpc_rate_limits_expiry ON catdex_rpc_rate_limits(window_start);
CREATE TABLE IF NOT EXISTS catdex_audit_ledger (
  sequence BIGSERIAL PRIMARY KEY, actor_hash TEXT NOT NULL, action TEXT NOT NULL,
  outcome TEXT NOT NULL CHECK (outcome IN ('ok','rejected')), request_id TEXT NOT NULL DEFAULT '',
  latency_ms BIGINT NOT NULL CHECK (latency_ms >= 0), created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS catdex_audit_ledger_created ON catdex_audit_ledger(created_at);
CREATE INDEX IF NOT EXISTS catdex_audit_ledger_actor ON catdex_audit_ledger(actor_hash,created_at DESC);
CREATE TABLE IF NOT EXISTS catdex_deletion_challenges (
  user_id UUID PRIMARY KEY, challenge UUID NOT NULL UNIQUE, expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS catdex_deletion_challenges_expiry ON catdex_deletion_challenges(expires_at);
DO $$ BEGIN
  ALTER TABLE catdex_inventory ADD CONSTRAINT catdex_inventory_meter_bounds
    CHECK (level BETWEEN 1 AND 100 AND xp >= 0 AND energy BETWEEN 0 AND 100
      AND hunger BETWEEN 0 AND 100 AND mood BETWEEN 0 AND 100
      AND bond BETWEEN 0 AND 100 AND ability_mastery BETWEEN 0 AND 100) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE catdex_events ADD CONSTRAINT catdex_events_bounds
    CHECK (progress >= 0 AND ends_at > starts_at AND radius_m BETWEEN 25 AND 10000
      AND per_user_cap > 0 AND per_user_cap <= goal
      AND latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE catdex_enrollments ADD CONSTRAINT catdex_enrollment_geo_bounds
    CHECK ((lat IS NULL OR lat BETWEEN -90 AND 90)
      AND (lng IS NULL OR lng BETWEEN -180 AND 180)
      AND (accuracy_m IS NULL OR accuracy_m BETWEEN 0 AND 100000)) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE INDEX IF NOT EXISTS catdex_events_active ON catdex_events(starts_at,ends_at);
CREATE INDEX IF NOT EXISTS catdex_battles_user_created ON catdex_battles(user_id,created_at DESC);
CREATE INDEX IF NOT EXISTS catdex_event_contributions_created ON catdex_event_contributions(created_at);
`
	_, err := db.ExecContext(ctx, schema)
	return err
}
