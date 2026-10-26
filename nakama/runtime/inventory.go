package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

func invalid(err error) error {
	return runtime.NewError(err.Error(), 3)
}

func rpcHealth(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if err := db.PingContext(ctx); err != nil {
		return "", runtime.NewError("database unavailable", 14)
	}
	return `{"ok":true,"service":"catdex-runtime","version":"1.0.0"}`, nil
}

func rpcBootstrap(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var count int
	if err := db.QueryRowContext(ctx, `SELECT count(*) FROM catdex_inventory WHERE user_id=$1`, uid).Scan(&count); err != nil {
		return "", err
	}
	return encodeJSON(map[string]any{
		"userId": uid, "inventoryCount": count, "serverTime": time.Now().UTC(),
		"minimumClientVersion": envOrDefault("CATDEX_MIN_CLIENT_VERSION", "1.0.0"),
		"rulesVersion":         envOrDefault("CATDEX_MIN_RULES_VERSION", "1"),
		"features": map[string]bool{
			"inventoryWrites": featureEnabled("inventory_writes"),
			"enrollment":      featureEnabled("enrollment"),
			"progression":     featureEnabled("progression"),
			"events":          featureEnabled("events"),
			"battle":          featureEnabled("battle"),
			"accountTools":    featureEnabled("account_tools"),
		},
	})
}

func envOrDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

type inventoryResponse struct {
	Cards []Card `json:"cards"`
}

func rpcGetInventory(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	rows, err := db.QueryContext(ctx, `SELECT card, level, xp, energy, hunger, mood, bond, ability_mastery,
		last_fed_at,last_played_at,last_groomed_at,last_trained_at,last_rested_at,progression_updated_at
		FROM catdex_inventory WHERE user_id=$1 ORDER BY created_at, card_id`, uid)
	if err != nil {
		return "", err
	}
	defer rows.Close()
	out := inventoryResponse{Cards: []Card{}}
	for rows.Next() {
		var raw []byte
		var c Card
		var level, xp, energy, hunger, mood, bond, mastery int
		var fed, played, groomed, trained, rested sql.NullTime
		var updated time.Time
		if err := rows.Scan(&raw, &level, &xp, &energy, &hunger, &mood, &bond,
			&mastery, &fed, &played, &groomed, &trained, &rested, &updated); err != nil {
			return "", err
		}
		if err := json.Unmarshal(raw, &c); err != nil {
			return "", fmt.Errorf("stored card is invalid: %w", err)
		}
		c.Level, c.XP = level, xp
		c.Energy, c.Hunger, c.Mood, c.Bond, c.AbilityMastery = energy, hunger, mood, bond, mastery
		c.LastFedAt, c.LastPlayedAt, c.LastGroomedAt = timePtr(fed), timePtr(played), timePtr(groomed)
		c.LastTrainedAt, c.LastRestedAt, c.ProgressionUpdatedAt = timePtr(trained), timePtr(rested), &updated
		out.Cards = append(out.Cards, c)
	}
	if err := rows.Err(); err != nil {
		return "", err
	}
	return encodeJSON(out)
}

func timePtr(value sql.NullTime) *time.Time {
	if !value.Valid {
		return nil
	}
	t := value.Time.UTC()
	return &t
}

type upsertInventoryRequest struct {
	Cards []Card `json:"cards"`
	// Accepted for compatibility but never trusted for authorization.
	UserID    string `json:"userId,omitempty"`
	UpdatedAt string `json:"updatedAt,omitempty"`
}

func rpcUpsertInventory(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req upsertInventoryRequest
	if err := decodeJSON(payload, &req); err != nil {
		return "", invalid(err)
	}
	if len(req.Cards) > 500 {
		return "", invalid(fmt.Errorf("at most 500 cards"))
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	for i := range req.Cards {
		c := &req.Cards[i]
		if err := validateCard(c); err != nil {
			return "", err
		}
		if c.CreatedAt == "" {
			c.CreatedAt = time.Now().UTC().Format(time.RFC3339)
		}
		raw, err := json.Marshal(c)
		if err != nil {
			return "", invalid(err)
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO catdex_inventory(user_id,card_id,card,level,xp,base_stats)
			VALUES($1,$2,$3,$4,$5,$3::jsonb->'stats') ON CONFLICT(user_id,card_id) DO UPDATE
			SET card=catdex_inventory.card || jsonb_build_object(
				'name', EXCLUDED.card->'name',
				'accentColor', EXCLUDED.card->'accentColor',
				'sticker', EXCLUDED.card->'sticker'
			), updated_at=now()`,
			uid, c.ID, raw, max(1, c.Level), max(0, c.XP))
		if err != nil {
			return "", err
		}
	}
	if err := tx.Commit(); err != nil {
		return "", err
	}
	return encodeJSON(map[string]any{"upserted": len(req.Cards)})
}
