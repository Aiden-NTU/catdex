package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

const (
	maxCatLevel  = 40
	dailyCoinCap = 100
)

type careRequest struct {
	RequestID string `json:"requestId"`
	CardID    string `json:"cardId"`
	Action    string `json:"action"`
}

type careStateRequest struct {
	CardID string `json:"cardId"`
}

type careAccount struct {
	PawCoins         int    `json:"pawCoins"`
	DailyEarned      int    `json:"dailyEarned"`
	DailyCap         int    `json:"dailyCap"`
	Treats           int    `json:"treats"`
	GroomingSupplies int    `json:"groomingSupplies"`
	DayBucket        string `json:"dayBucket"`
}

type careResponse struct {
	Card            Card        `json:"card"`
	Account         careAccount `json:"account"`
	Action          string      `json:"action,omitempty"`
	XPAwarded       int         `json:"xpAwarded"`
	CoinsAwarded    int         `json:"coinsAwarded"`
	CooldownSeconds int         `json:"cooldownSeconds,omitempty"`
	Idempotent      bool        `json:"idempotent"`
}

type careRule struct {
	cooldown         time.Duration
	xp, coins        int
	energy, hunger   int
	mood, bond       int
	mastery          int
	treats, grooming int
	timestampColumn  string
}

var careRules = map[string]careRule{
	"feed":  {30 * time.Minute, 15, 2, 0, 20, 5, 10, 0, -1, 0, "last_fed_at"},
	"play":  {20 * time.Minute, 20, 3, -15, 0, 15, 8, 0, 0, 0, "last_played_at"},
	"groom": {4 * time.Hour, 20, 3, 0, 0, 10, 12, 0, 0, -1, "last_groomed_at"},
	"train": {time.Hour, 30, 4, -20, 0, 0, 5, 10, 0, 0, "last_trained_at"},
	"rest":  {15 * time.Minute, 0, 0, 30, 0, 3, 0, 0, 0, 0, "last_rested_at"},
}

func rpcGetCareState(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req careStateRequest
	if err := decodeJSON(payload, &req); err != nil || strings.TrimSpace(req.CardID) == "" {
		return "", errInvalidArgument
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	account, err := loadAccount(ctx, tx, uid, time.Now().UTC())
	if err != nil {
		return "", err
	}
	card, err := loadCareCard(ctx, tx, uid, req.CardID, false)
	if err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", err
	}
	return encodeJSON(careResponse{Card: card, Account: account})
}

func rpcCareAction(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req careRequest
	if err := decodeJSON(payload, &req); err != nil {
		return "", invalid(err)
	}
	req.RequestID, req.CardID, req.Action = strings.TrimSpace(req.RequestID), strings.TrimSpace(req.CardID), strings.ToLower(strings.TrimSpace(req.Action))
	rule, ok := careRules[req.Action]
	if !ok || req.RequestID == "" || len(req.RequestID) > 128 || req.CardID == "" || len(req.CardID) > 128 {
		return "", errInvalidArgument
	}
	now := time.Now().UTC()
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, uid); err != nil {
		return "", err
	}
	var priorRaw []byte
	var priorCard, priorAction string
	err = tx.QueryRowContext(ctx, `SELECT card_id,action,response FROM catdex_economy_ledger WHERE user_id=$1 AND request_id=$2`, uid, req.RequestID).Scan(&priorCard, &priorAction, &priorRaw)
	if err == nil {
		if priorCard != req.CardID || priorAction != req.Action {
			return "", errConflict
		}
		var prior careResponse
		if json.Unmarshal(priorRaw, &prior) != nil {
			return "", fmt.Errorf("invalid ledger response")
		}
		prior.Idempotent = true
		return encodeJSON(prior)
	}
	if err != sql.ErrNoRows {
		return "", err
	}
	account, err := loadAccount(ctx, tx, uid, now)
	if err != nil {
		return "", err
	}
	card, err := loadCareCard(ctx, tx, uid, req.CardID, true)
	if err != nil {
		return "", err
	}
	lastAction := careTimestamp(card, req.Action)
	if lastAction != nil && now.Sub(*lastAction) < rule.cooldown {
		remaining := int((rule.cooldown - now.Sub(*lastAction)).Seconds()) + 1
		return "", runtime.NewError(fmt.Sprintf("%s cooldown active; retry in %d seconds", req.Action, remaining), 9)
	}
	if account.Treats+rule.treats < 0 || account.GroomingSupplies+rule.grooming < 0 {
		return "", runtime.NewError("care resource unavailable", 9)
	}
	if card.Energy+rule.energy < 0 {
		return "", runtime.NewError("not enough energy; let your cat rest", 9)
	}
	if (req.Action == "feed" && card.Hunger >= 100) || (req.Action == "rest" && card.Energy >= 100) {
		return "", runtime.NewError("that meter is already full", 9)
	}
	card.Energy = clamp(card.Energy+rule.energy, 0, 100)
	card.Hunger = clamp(card.Hunger+rule.hunger, 0, 100)
	card.Mood = clamp(card.Mood+rule.mood, 0, 100)
	card.Bond = clamp(card.Bond+rule.bond, 0, 100)
	card.AbilityMastery = clamp(card.AbilityMastery+rule.mastery, 0, 100)
	card.XP = min(totalXPForLevel(maxCatLevel), card.XP+rule.xp)
	card.Level = levelForXP(card.XP)
	setCareTimestamp(&card, req.Action, now)
	card.ProgressionUpdatedAt = &now
	account.Treats += rule.treats
	account.GroomingSupplies += rule.grooming
	coins := min(rule.coins, max(0, dailyCoinCap-account.DailyEarned))
	account.PawCoins += coins
	account.DailyEarned += coins
	deriveBattleStats(&card)
	cardRaw, _ := json.Marshal(card)
	_, err = tx.ExecContext(ctx, fmt.Sprintf(`UPDATE catdex_inventory SET card=$3,level=$4,xp=$5,energy=$6,hunger=$7,mood=$8,bond=$9,
		ability_mastery=$10,%s=$11,progression_updated_at=$11,updated_at=$11 WHERE user_id=$1 AND card_id=$2`, rule.timestampColumn),
		uid, req.CardID, cardRaw, card.Level, card.XP, card.Energy, card.Hunger, card.Mood, card.Bond, card.AbilityMastery, now)
	if err != nil {
		return "", err
	}
	_, err = tx.ExecContext(ctx, `UPDATE catdex_accounts SET paw_coins=$2,daily_earned=$3,treats=$4,grooming_supplies=$5,updated_at=$6 WHERE user_id=$1`,
		uid, account.PawCoins, account.DailyEarned, account.Treats, account.GroomingSupplies, now)
	if err != nil {
		return "", err
	}
	out := careResponse{Card: card, Account: account, Action: req.Action, XPAwarded: rule.xp, CoinsAwarded: coins, CooldownSeconds: int(rule.cooldown.Seconds())}
	responseRaw, _ := json.Marshal(out)
	_, err = tx.ExecContext(ctx, `INSERT INTO catdex_economy_ledger(user_id,request_id,card_id,action,xp_delta,coin_delta,treats_delta,grooming_delta,response)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`, uid, req.RequestID, req.CardID, req.Action, rule.xp, coins, rule.treats, rule.grooming, responseRaw)
	if err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", errConflict
	}
	return string(responseRaw), nil
}

func loadAccount(ctx context.Context, tx *sql.Tx, uid string, now time.Time) (careAccount, error) {
	if _, err := tx.ExecContext(ctx, `INSERT INTO catdex_accounts(user_id) VALUES($1) ON CONFLICT DO NOTHING`, uid); err != nil {
		return careAccount{}, err
	}
	var out careAccount
	var day time.Time
	err := tx.QueryRowContext(ctx, `SELECT paw_coins,daily_earned,treats,grooming_supplies,day_bucket FROM catdex_accounts WHERE user_id=$1 FOR UPDATE`, uid).
		Scan(&out.PawCoins, &out.DailyEarned, &out.Treats, &out.GroomingSupplies, &day)
	if err != nil {
		return out, err
	}
	today := now.Format("2006-01-02")
	if day.UTC().Format("2006-01-02") != today {
		out.DailyEarned = 0
		out.Treats = min(20, out.Treats+3)
		out.GroomingSupplies = min(10, out.GroomingSupplies+1)
		if _, err := tx.ExecContext(ctx, `UPDATE catdex_accounts SET daily_earned=0,day_bucket=$2,treats=$3,grooming_supplies=$4,updated_at=$5 WHERE user_id=$1`,
			uid, today, out.Treats, out.GroomingSupplies, now); err != nil {
			return out, err
		}
	}
	out.DailyCap, out.DayBucket = dailyCoinCap, today
	return out, nil
}

func loadCareCard(ctx context.Context, tx *sql.Tx, uid, cardID string, lock bool) (Card, error) {
	query := `SELECT card,level,xp,energy,hunger,mood,bond,ability_mastery,base_stats,
		last_fed_at,last_played_at,last_groomed_at,last_trained_at,last_rested_at,progression_updated_at
		FROM catdex_inventory WHERE user_id=$1 AND card_id=$2`
	if lock {
		query += ` FOR UPDATE`
	}
	var raw, baseRaw []byte
	var card Card
	var fed, played, groomed, trained, rested sql.NullTime
	var updated time.Time
	err := tx.QueryRowContext(ctx, query, uid, cardID).Scan(&raw, &card.Level, &card.XP, &card.Energy, &card.Hunger, &card.Mood,
		&card.Bond, &card.AbilityMastery, &baseRaw, &fed, &played, &groomed, &trained, &rested, &updated)
	if err == sql.ErrNoRows {
		return card, errNotFound
	}
	if err != nil {
		return card, err
	}
	if err := json.Unmarshal(raw, &card); err != nil {
		return card, err
	}
	// Authoritative columns overwrite any stale client-supplied JSON.
	err = tx.QueryRowContext(ctx, `SELECT level,xp,energy,hunger,mood,bond,ability_mastery FROM catdex_inventory WHERE user_id=$1 AND card_id=$2`,
		uid, cardID).Scan(&card.Level, &card.XP, &card.Energy, &card.Hunger, &card.Mood, &card.Bond, &card.AbilityMastery)
	if err != nil {
		return card, err
	}
	if len(baseRaw) > 0 {
		_ = json.Unmarshal(baseRaw, &card.Stats)
		deriveBattleStats(&card)
	}
	card.LastFedAt, card.LastPlayedAt, card.LastGroomedAt = timePtr(fed), timePtr(played), timePtr(groomed)
	card.LastTrainedAt, card.LastRestedAt, card.ProgressionUpdatedAt = timePtr(trained), timePtr(rested), &updated
	return card, nil
}

func totalXPForLevel(level int) int {
	n := level - 1
	return 100 * n * (n + 1) * (2*n + 1) / 6
}

func levelForXP(xp int) int {
	level := 1
	for level < maxCatLevel && xp >= totalXPForLevel(level+1) {
		level++
	}
	return level
}

func deriveBattleStats(card *Card) {
	bonus := float64(card.Level-1)*0.01 + float64(card.AbilityMastery)*0.002
	card.Stats.Attack = clamp(int(float64(card.Stats.Attack)*(1+bonus)+0.5), 1, 250)
	card.Stats.Defense = clamp(int(float64(card.Stats.Defense)*(1+bonus)+0.5), 1, 250)
	card.Stats.Speed = clamp(int(float64(card.Stats.Speed)*(1+bonus)+0.5), 1, 250)
	card.Stats.BattlePower = card.Stats.Attack + card.Stats.Defense + card.Stats.Speed
}

func careTimestamp(card Card, action string) *time.Time {
	switch action {
	case "feed":
		return card.LastFedAt
	case "play":
		return card.LastPlayedAt
	case "groom":
		return card.LastGroomedAt
	case "train":
		return card.LastTrainedAt
	default:
		return card.LastRestedAt
	}
}

func setCareTimestamp(card *Card, action string, now time.Time) {
	switch action {
	case "feed":
		card.LastFedAt = &now
	case "play":
		card.LastPlayedAt = &now
	case "groom":
		card.LastGroomedAt = &now
	case "train":
		card.LastTrainedAt = &now
	case "rest":
		card.LastRestedAt = &now
	}
}

func clamp(value, low, high int) int {
	return min(high, max(low, value))
}
