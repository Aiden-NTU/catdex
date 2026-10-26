package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	h3 "github.com/uber/h3-go/v4"
	"github.com/heroiclabs/nakama-common/runtime"
)

func rpcAccountExport(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req struct {
		Confirm string `json:"confirm"`
	}
	if err := decodeJSON(payload, &req); err != nil || req.Confirm != "EXPORT" {
		return "", runtime.NewError("confirm must equal EXPORT", 3)
	}
	var inventory, enrollments, contributions, battles json.RawMessage
	err = db.QueryRowContext(ctx, `SELECT
		COALESCE((SELECT jsonb_agg(jsonb_build_object('card',card,'level',level,'xp',xp,'createdAt',created_at,'updatedAt',updated_at) ORDER BY created_at)
			FROM catdex_inventory WHERE user_id=$1),'[]'::jsonb),
		COALESCE((SELECT jsonb_agg(jsonb_build_object('cardId',card_id,'h3Cell',h3_cell,'capturedAt',captured_at,'createdAt',created_at) ORDER BY created_at)
			FROM catdex_enrollments WHERE user_id=$1),'[]'::jsonb),
		COALESCE((SELECT jsonb_agg(jsonb_build_object('eventId',event_id,'amount',amount,'type',contribution_type,'createdAt',created_at) ORDER BY created_at)
			FROM catdex_event_contributions WHERE user_id=$1),'[]'::jsonb),
		COALESCE((SELECT jsonb_agg(jsonb_build_object('battleId',id,'result',result,'createdAt',created_at) ORDER BY created_at)
			FROM catdex_battles WHERE user_id=$1),'[]'::jsonb)`, uid).
		Scan(&inventory, &enrollments, &contributions, &battles)
	if err != nil {
		return "", err
	}
	return encodeJSON(map[string]any{
		"formatVersion": 1, "exportedAt": time.Now().UTC(), "userId": uid,
		"inventory": inventory, "enrollments": enrollments,
		"eventContributions": contributions, "battles": battles,
	})
}

func rpcAccountDelete(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req struct {
		Challenge string `json:"challenge,omitempty"`
		Confirm   string `json:"confirm,omitempty"`
	}
	if err := decodeJSON(payload, &req); err != nil {
		return "", errInvalidArgument
	}
	if req.Challenge == "" || req.Confirm != "DELETE MY CATDEX ACCOUNT" {
		challenge, err := newUUID()
		if err != nil {
			return "", err
		}
		_, err = db.ExecContext(ctx, `INSERT INTO catdex_deletion_challenges(user_id,challenge,expires_at)
			VALUES($1,$2,now()+interval '10 minutes')
			ON CONFLICT(user_id) DO UPDATE SET challenge=EXCLUDED.challenge,expires_at=EXCLUDED.expires_at`, uid, challenge)
		if err != nil {
			return "", err
		}
		return encodeJSON(map[string]any{
			"deleted": false, "challenge": challenge,
			"expiresInSeconds": 600, "requiredConfirmation": "DELETE MY CATDEX ACCOUNT",
		})
	}

	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	var valid bool
	if err := tx.QueryRowContext(ctx, `DELETE FROM catdex_deletion_challenges
		WHERE user_id=$1 AND challenge=$2 AND expires_at>now() RETURNING true`, uid, req.Challenge).Scan(&valid); err != nil {
		if err == sql.ErrNoRows {
			return "", runtime.NewError("deletion challenge invalid or expired", 9)
		}
		return "", err
	}
	for _, query := range []string{
		`DELETE FROM catdex_battle_action_ids WHERE match_id IN (SELECT id FROM catdex_battle_matches WHERE player_a_user_id=$1 OR player_b_user_id=$1)`,
		`DELETE FROM catdex_battle_matches WHERE player_a_user_id=$1 OR player_b_user_id=$1`,
		`DELETE FROM catdex_battles WHERE user_id=$1 OR opponent_user_id=$1`,
		`DELETE FROM catdex_event_rewards WHERE user_id=$1`,
		`DELETE FROM catdex_event_contributions WHERE user_id=$1`,
		`DELETE FROM catdex_feed_ledger WHERE user_id=$1`,
		`DELETE FROM catdex_enrollments WHERE user_id=$1`,
		`DELETE FROM catdex_economy_ledger WHERE user_id=$1`,
		`DELETE FROM catdex_inventory WHERE user_id=$1`,
		`DELETE FROM catdex_accounts WHERE user_id=$1`,
	} {
		if _, err := tx.ExecContext(ctx, query, uid); err != nil {
			return "", err
		}
	}
	if err := tx.Commit(); err != nil {
		return "", err
	}
	if err := nk.AccountDeleteId(ctx, uid, true); err != nil {
		return "", fmt.Errorf("delete nakama account: %w", err)
	}
	return `{"deleted":true}`, nil
}

func rpcAdminSeedEvent(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := requireAdmin(ctx)
	if err != nil {
		return "", err
	}
	var req struct {
		Kind        string         `json:"kind"`
		Title       string         `json:"title"`
		Description string         `json:"description"`
		H3Cell      string         `json:"h3Cell"`
		Goal        int            `json:"goal"`
		RadiusM     int            `json:"radiusM"`
		PerUserCap  int            `json:"perUserCap"`
		Latitude    float64        `json:"latitude"`
		Longitude   float64        `json:"longitude"`
		StartsAt    time.Time      `json:"startsAt"`
		EndsAt      time.Time      `json:"endsAt"`
		Metadata    map[string]any `json:"metadata"`
	}
	if decodeJSON(payload, &req) != nil || len(req.Title) < 1 || len(req.Title) > 120 ||
		len(req.Description) > 500 || req.Goal < 1 || req.Goal > 100000 ||
		req.PerUserCap < 1 || req.PerUserCap > req.Goal || req.RadiusM < 25 || req.RadiusM > 10000 ||
		req.StartsAt.Before(time.Now().UTC().Add(-5*time.Minute)) || !req.EndsAt.After(req.StartsAt) ||
		req.EndsAt.Sub(req.StartsAt) > 7*24*time.Hour {
		return "", errInvalidArgument
	}
	cell := h3.Cell(0)
	if err := cell.UnmarshalText([]byte(req.H3Cell)); err != nil || cell.Resolution() != h3Resolution {
		return "", errInvalidArgument
	}
	switch req.Kind {
	case "cat_cafe_rally", "cardboard_fortress", "laser_pointer_chase":
	default:
		return "", errInvalidArgument
	}
	id, err := newUUID()
	if err != nil {
		return "", err
	}
	metadata, err := json.Marshal(req.Metadata)
	if err != nil || len(metadata) > 8*1024 {
		return "", errInvalidArgument
	}
	_, err = db.ExecContext(ctx, `INSERT INTO catdex_events
		(id,h3_cell,kind,title,description,goal,starts_at,ends_at,radius_m,per_user_cap,latitude,longitude,metadata)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)`,
		id, req.H3Cell, req.Kind, req.Title, req.Description, req.Goal, req.StartsAt, req.EndsAt,
		req.RadiusM, req.PerUserCap, req.Latitude, req.Longitude, metadata)
	if err != nil {
		return "", err
	}
	logger.Info("admin event seeded actor=%s event=%s kind=%s", auditIdentity(uid), id, req.Kind)
	return encodeJSON(map[string]any{"eventId": id})
}

func rpcAdminRetention(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if _, err := requireAdmin(ctx); err != nil {
		return "", err
	}
	var req struct {
		Confirm string `json:"confirm"`
	}
	if decodeJSON(payload, &req) != nil || req.Confirm != "RUN RETENTION" {
		return "", errInvalidArgument
	}
	auditDays := boundedEnvDays("CATDEX_AUDIT_RETENTION_DAYS", 90, 30, 730)
	ledgerDays := boundedEnvDays("CATDEX_LEDGER_RETENTION_DAYS", 730, 90, 3650)
	result := map[string]int64{}
	for name, query := range map[string]string{
		"rateLimits": `DELETE FROM catdex_rpc_rate_limits WHERE window_start < now()-interval '2 days'`,
		"challenges": `DELETE FROM catdex_deletion_challenges WHERE expires_at < now()`,
		"audit":      `DELETE FROM catdex_audit_ledger WHERE created_at < now()-($1 * interval '1 day')`,
		"ledgers":    `DELETE FROM catdex_economy_ledger WHERE created_at < now()-($1 * interval '1 day')`,
	} {
		days := auditDays
		if name == "ledgers" {
			days = ledgerDays
		}
		res, err := db.ExecContext(ctx, query, days)
		if err != nil {
			return "", err
		}
		result[name], _ = res.RowsAffected()
	}
	return encodeJSON(map[string]any{"deletedRows": result})
}

func requireAdmin(ctx context.Context) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	for _, allowed := range strings.Split(os.Getenv("CATDEX_ADMIN_USER_IDS"), ",") {
		if strings.TrimSpace(allowed) == uid {
			return uid, nil
		}
	}
	return "", runtime.NewError("permission denied", 7)
}

func boundedEnvDays(name string, fallback, minimum, maximum int) int {
	value, err := strconv.Atoi(os.Getenv(name))
	if err != nil || value < minimum || value > maximum {
		return fallback
	}
	return value
}
