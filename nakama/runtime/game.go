package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
	h3 "github.com/uber/h3-go/v4"
)

type feedRequest struct {
	RequestID string `json:"requestId"`
	CardID    string `json:"cardId"`
	Amount    int    `json:"amount"`
}

func rpcFeed(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req feedRequest
	if err := decodeJSON(payload, &req); err != nil {
		return "", invalid(err)
	}
	if req.RequestID == "" || len(req.RequestID) > 128 || req.CardID == "" || req.Amount < 1 || req.Amount > 10 {
		return "", errInvalidArgument
	}
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	var xpAwarded int
	var priorCardID string
	err = tx.QueryRowContext(ctx, `SELECT card_id,xp_awarded FROM catdex_feed_ledger WHERE user_id=$1 AND request_id=$2`,
		uid, req.RequestID).Scan(&priorCardID, &xpAwarded)
	if err == nil {
		if priorCardID != req.CardID {
			return "", errConflict
		}
		var level, xp int
		if err := tx.QueryRowContext(ctx, `SELECT level,xp FROM catdex_inventory WHERE user_id=$1 AND card_id=$2`, uid, req.CardID).Scan(&level, &xp); err != nil {
			return "", err
		}
		return encodeJSON(map[string]any{"cardId": req.CardID, "level": level, "xp": xp, "xpAwarded": xpAwarded, "idempotent": true})
	}
	if err != sql.ErrNoRows {
		return "", err
	}
	xpAwarded = req.Amount * 10
	var xp int
	if err := tx.QueryRowContext(ctx, `SELECT xp FROM catdex_inventory WHERE user_id=$1 AND card_id=$2 FOR UPDATE`, uid, req.CardID).Scan(&xp); err == sql.ErrNoRows {
		return "", errNotFound
	} else if err != nil {
		return "", err
	}
	xp = min(totalXPForLevel(maxCatLevel), xp+xpAwarded)
	level := levelForXP(xp)
	if _, err := tx.ExecContext(ctx, `UPDATE catdex_inventory SET xp=$3,level=$4,progression_updated_at=now(),updated_at=now()
		WHERE user_id=$1 AND card_id=$2`, uid, req.CardID, xp, level); err != nil {
		return "", err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO catdex_feed_ledger(user_id,request_id,card_id,amount,xp_awarded) VALUES($1,$2,$3,$4,$5)`,
		uid, req.RequestID, req.CardID, req.Amount, xpAwarded); err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", errConflict
	}
	return encodeJSON(map[string]any{"cardId": req.CardID, "level": level, "xp": xp, "xpAwarded": xpAwarded, "idempotent": false})
}

type nearbyRequest struct {
	H3Cells []string `json:"h3Cells"`
}

func rpcNearbyEvents(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	if _, err := userID(ctx); err != nil {
		return "", err
	}
	var req nearbyRequest
	if err := decodeJSON(payload, &req); err != nil {
		return "", invalid(err)
	}
	if len(req.H3Cells) == 0 || len(req.H3Cells) > 32 {
		return "", errInvalidArgument
	}
	origin := h3.Cell(h3.IndexFromString(req.H3Cells[0]))
	if origin == 0 || origin.Resolution() != h3Resolution {
		return "", errInvalidArgument
	}
	for _, cell := range req.H3Cells {
		if cell == "" || len(cell) > 32 {
			return "", errInvalidArgument
		}
		candidate := h3.Cell(h3.IndexFromString(cell))
		distance, err := h3.GridDistance(origin, candidate)
		if candidate == 0 || candidate.Resolution() != h3Resolution || err != nil || distance > 1 {
			return "", errInvalidArgument
		}
	}
	uid, _ := userID(ctx)
	cellsJSON, _ := json.Marshal(req.H3Cells)
	rows, err := db.QueryContext(ctx, `SELECT e.id,e.h3_cell,e.kind,e.title,e.description,e.goal,e.progress,
		e.radius_m,e.per_user_cap,e.starts_at,e.ends_at,e.latitude,e.longitude,e.metadata,
		COALESCE((SELECT sum(c.amount) FROM catdex_event_contributions c WHERE c.event_id=e.id AND c.user_id=$2),0),
		EXISTS(SELECT 1 FROM catdex_event_rewards r WHERE r.event_id=e.id AND r.user_id=$2)
		FROM catdex_events e WHERE e.h3_cell IN (SELECT jsonb_array_elements_text($1::jsonb))
		AND e.ends_at>now()-interval '24 hours' ORDER BY e.ends_at LIMIT 100`, cellsJSON, uid)
	if err != nil {
		return "", err
	}
	defer rows.Close()
	events := []nearbyEvent{}
	for rows.Next() {
		var e nearbyEvent
		var metadata []byte
		if err := rows.Scan(&e.ID, &e.H3Cell, &e.Kind, &e.Title, &e.Description, &e.Goal,
			&e.Progress, &e.RadiusM, &e.PerUserCap, &e.StartsAt, &e.EndsAt,
			&e.Latitude, &e.Longitude, &metadata, &e.MyContribution, &e.RewardClaimed); err != nil {
			return "", err
		}
		_ = json.Unmarshal(metadata, &e.Metadata)
		now := time.Now()
		switch {
		case now.Before(e.StartsAt):
			e.State = "scheduled"
		case now.Before(e.EndsAt):
			e.State = "active"
		default:
			e.State = "ended"
		}
		events = append(events, e)
	}
	return encodeJSON(map[string]any{"events": events})
}

type contributionRequest struct {
	RequestID  string  `json:"requestId"`
	EventID    string  `json:"eventId"`
	Amount     int     `json:"amount"`
	H3Cell     string  `json:"h3Cell"`
	Lat        float64 `json:"lat"`
	Lng        float64 `json:"lng"`
	AccuracyM  float64 `json:"accuracyM"`
	Type       string  `json:"type"`
	SquadID    string  `json:"squadId,omitempty"`
	Checkpoint string  `json:"checkpointId,omitempty"`
	Stationary bool    `json:"stationary,omitempty"`
}

func rpcContributeEvent(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req contributionRequest
	if err := decodeJSON(payload, &req); err != nil {
		return "", invalid(err)
	}
	if req.RequestID == "" || len(req.RequestID) > 128 || req.EventID == "" ||
		req.Amount < 1 || req.Amount > 100 || req.H3Cell == "" ||
		req.AccuracyM < 0 || req.AccuracyM > 250 || math.Abs(req.Lat) > 90 || math.Abs(req.Lng) > 180 {
		return "", errInvalidArgument
	}
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	var previous int
	var priorEventID string
	err = tx.QueryRowContext(ctx, `SELECT event_id,amount FROM catdex_event_contributions WHERE user_id=$1 AND request_id=$2`, uid, req.RequestID).Scan(&priorEventID, &previous)
	if err == nil {
		if priorEventID != req.EventID {
			return "", errConflict
		}
		var progress, goal int
		if err := tx.QueryRowContext(ctx, `SELECT progress,goal FROM catdex_events WHERE id=$1`, req.EventID).Scan(&progress, &goal); err != nil {
			return "", err
		}
		return encodeJSON(map[string]any{"eventId": req.EventID, "progress": progress, "goal": goal, "accepted": previous, "idempotent": true})
	}
	if err != sql.ErrNoRows {
		return "", err
	}
	var progress, goal, radius, userCap, personalReward, communityReward int
	var kind, eventCell string
	var eventLat, eventLng float64
	var metadataRaw []byte
	err = tx.QueryRowContext(ctx, `SELECT progress,goal,kind,h3_cell,radius_m,per_user_cap,
		latitude,longitude,metadata,personal_reward,community_reward FROM catdex_events
		WHERE id=$1 AND starts_at<=now() AND ends_at>now() FOR UPDATE`, req.EventID).
		Scan(&progress, &goal, &kind, &eventCell, &radius, &userCap, &eventLat, &eventLng,
			&metadataRaw, &personalReward, &communityReward)
	if err == sql.ErrNoRows {
		return "", errNotFound
	}
	if err != nil {
		return "", err
	}
	if !eligibleEventLocation(req, eventCell, eventLat, eventLng, radius) {
		return "", runtime.NewError("outside event area", 9)
	}
	var metadata map[string]any
	_ = json.Unmarshal(metadataRaw, &metadata)
	if err := validateEventContribution(kind, req, metadata); err != nil {
		return "", err
	}
	var userTotal int
	if err := tx.QueryRowContext(ctx, `SELECT COALESCE(sum(amount),0) FROM catdex_event_contributions
		WHERE event_id=$1 AND user_id=$2`, req.EventID, uid).Scan(&userTotal); err != nil {
		return "", err
	}
	accepted := min(req.Amount, max(0, min(goal-progress, userCap-userTotal)))
	if kind == "cat_cafe_rally" {
		var treats int
		if err := tx.QueryRowContext(ctx, `INSERT INTO catdex_accounts(user_id) VALUES($1)
			ON CONFLICT(user_id) DO UPDATE SET updated_at=catdex_accounts.updated_at
			RETURNING treats`, uid).Scan(&treats); err != nil {
			return "", err
		}
		accepted = min(accepted, treats)
		if accepted > 0 {
			if _, err := tx.ExecContext(ctx, `UPDATE catdex_accounts SET treats=treats-$2,updated_at=now()
				WHERE user_id=$1`, uid, accepted); err != nil {
				return "", err
			}
		}
	}
	completedNow := progress < goal && progress+accepted >= goal
	progress += accepted
	if _, err := tx.ExecContext(ctx, `UPDATE catdex_events SET progress=$2 WHERE id=$1`, req.EventID, progress); err != nil {
		return "", err
	}
	if accepted == 0 {
		return "", errConflict
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO catdex_event_contributions
		(event_id,user_id,request_id,amount,contribution_type,squad_id,checkpoint_id)
		VALUES($1,$2,$3,$4,$5,NULLIF($6,''),NULLIF($7,''))`,
		req.EventID, uid, req.RequestID, accepted, req.Type, req.SquadID, req.Checkpoint); err != nil {
		return "", err
	}
	personal := min(personalReward, accepted)
	community := 0
	if completedNow {
		community = communityReward
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO catdex_event_rewards
		(event_id,user_id,personal_reward,community_reward) VALUES($1,$2,$3,$4)
		ON CONFLICT(event_id,user_id) DO UPDATE SET
		personal_reward=GREATEST(catdex_event_rewards.personal_reward,EXCLUDED.personal_reward),
		community_reward=GREATEST(catdex_event_rewards.community_reward,EXCLUDED.community_reward)`,
		req.EventID, uid, personal, 0); err != nil {
		return "", err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO catdex_accounts(user_id,paw_coins) VALUES($1,$2)
		ON CONFLICT(user_id) DO UPDATE SET paw_coins=catdex_accounts.paw_coins+$2,updated_at=now()`,
		uid, personal); err != nil {
		return "", err
	}
	if completedNow {
		if _, err := tx.ExecContext(ctx, `INSERT INTO catdex_event_rewards(event_id,user_id,community_reward)
			SELECT $1,user_id,$2 FROM catdex_event_contributions WHERE event_id=$1 GROUP BY user_id
			ON CONFLICT(event_id,user_id) DO UPDATE SET community_reward=
				GREATEST(catdex_event_rewards.community_reward,EXCLUDED.community_reward)`,
			req.EventID, communityReward); err != nil {
			return "", err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE catdex_accounts a SET
			paw_coins=a.paw_coins+$2,updated_at=now() WHERE a.user_id IN
			(SELECT user_id FROM catdex_event_contributions WHERE event_id=$1)`,
			req.EventID, communityReward); err != nil {
			return "", err
		}
	}
	if err := tx.Commit(); err != nil {
		return "", errConflict
	}
	return encodeJSON(map[string]any{"eventId": req.EventID, "progress": progress, "goal": goal,
		"accepted": accepted, "personalReward": personal, "communityReward": community,
		"remainingCap": max(0, userCap-userTotal-accepted), "idempotent": false})
}

func eligibleEventLocation(req contributionRequest, eventCell string, lat, lng float64, radius int) bool {
	cell, err := h3.LatLngToCell(h3.NewLatLng(req.Lat, req.Lng), h3Resolution)
	if err != nil || cell.String() != strings.ToLower(req.H3Cell) {
		return false
	}
	event := h3.Cell(h3.IndexFromString(eventCell))
	if event == 0 {
		return false
	}
	distance, err := h3.GridDistance(cell, event)
	if err != nil || distance > 1 {
		return false
	}
	return haversineM(req.Lat, req.Lng, lat, lng) <= float64(radius)+req.AccuracyM
}

func validateEventContribution(kind string, req contributionRequest, metadata map[string]any) error {
	switch kind {
	case "cat_cafe_rally":
		if req.Type != "feed" {
			return errInvalidArgument
		}
	case "cardboard_fortress":
		if req.Type != "squad" || strings.TrimSpace(req.SquadID) == "" || len(req.SquadID) > 64 {
			return errInvalidArgument
		}
	case "laser_pointer_chase":
		if req.Type != "checkpoint" || strings.TrimSpace(req.Checkpoint) == "" {
			return errInvalidArgument
		}
		allowed := false
		for _, item := range anySlice(metadata["checkpoints"]) {
			if checkpoint, ok := item.(map[string]any); ok &&
				checkpoint["id"] == req.Checkpoint &&
				(req.Stationary || checkpoint["stationary"] != true) {
				allowed = true
			}
		}
		if !allowed {
			return errInvalidArgument
		}
	default:
		return errInvalidArgument
	}
	return nil
}

func rpcEventSummary(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req struct {
		EventID string `json:"eventId"`
	}
	if decodeJSON(payload, &req) != nil || req.EventID == "" {
		return "", errInvalidArgument
	}
	var title string
	var goal, progress, mine, contributors, personal, community int
	err = db.QueryRowContext(ctx, `SELECT e.title,e.goal,e.progress,
		COALESCE((SELECT sum(amount) FROM catdex_event_contributions WHERE event_id=e.id AND user_id=$2),0),
		(SELECT count(DISTINCT user_id) FROM catdex_event_contributions WHERE event_id=e.id),
		COALESCE((SELECT personal_reward FROM catdex_event_rewards WHERE event_id=e.id AND user_id=$2),0),
		COALESCE((SELECT community_reward FROM catdex_event_rewards WHERE event_id=e.id AND user_id=$2),0)
		FROM catdex_events e WHERE e.id=$1 AND e.ends_at<=now()`, req.EventID, uid).
		Scan(&title, &goal, &progress, &mine, &contributors, &personal, &community)
	if err == sql.ErrNoRows {
		return "", errNotFound
	}
	if err != nil {
		return "", err
	}
	return encodeJSON(map[string]any{"eventId": req.EventID, "title": title, "goal": goal,
		"progress": progress, "myContribution": mine, "contributors": contributors,
		"personalReward": personal, "communityReward": community, "completed": progress >= goal})
}

func anySlice(value any) []any {
	if values, ok := value.([]any); ok {
		return values
	}
	return nil
}

func haversineM(lat1, lng1, lat2, lng2 float64) float64 {
	const r = 6371000.0
	p1, p2 := lat1*math.Pi/180, lat2*math.Pi/180
	dp, dl := (lat2-lat1)*math.Pi/180, (lng2-lng1)*math.Pi/180
	a := math.Sin(dp/2)*math.Sin(dp/2) + math.Cos(p1)*math.Cos(p2)*math.Sin(dl/2)*math.Sin(dl/2)
	return 2 * r * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}

type opponentRequest struct {
	CardID string `json:"cardId"`
	H3Cell string `json:"h3Cell,omitempty"`
}

func rpcGetOpponent(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req opponentRequest
	if err := decodeJSON(payload, &req); err != nil {
		return "", invalid(err)
	}
	if req.CardID == "" {
		return "", errInvalidArgument
	}
	var exists bool
	if err := db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM catdex_inventory WHERE user_id=$1 AND card_id=$2)`, uid, req.CardID).Scan(&exists); err != nil {
		return "", err
	}
	if !exists {
		return "", errNotFound
	}
	var raw []byte
	err = db.QueryRowContext(ctx, `SELECT card FROM catdex_inventory
		WHERE user_id<>$1 AND authoritative AND ($2='' OR card->>'h3Cell'=$2) ORDER BY updated_at DESC,card_id LIMIT 1`, uid, req.H3Cell).Scan(&raw)
	if err == sql.ErrNoRows {
		return "", errNotFound
	}
	if err != nil {
		return "", err
	}
	var card Card
	if err := json.Unmarshal(raw, &card); err != nil {
		return "", err
	}
	card.Lat, card.Lng = nil, nil
	return encodeJSON(map[string]any{"opponent": card})
}

type battleRequest struct {
	RequestID      string `json:"requestId"`
	CardID         string `json:"cardId"`
	OpponentCardID string `json:"opponentCardId"`
}

func rpcResolveBattle(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req battleRequest
	if err := decodeJSON(payload, &req); err != nil {
		return "", invalid(err)
	}
	if req.RequestID == "" || len(req.RequestID) > 128 || req.CardID == "" || req.OpponentCardID == "" || req.CardID == req.OpponentCardID {
		return "", errInvalidArgument
	}
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	var prior []byte
	err = tx.QueryRowContext(ctx, `SELECT result FROM catdex_battles WHERE user_id=$1 AND request_id=$2`, uid, req.RequestID).Scan(&prior)
	if err == nil {
		return string(prior), nil
	}
	if err != sql.ErrNoRows {
		return "", err
	}
	var aRaw, bRaw []byte
	var opponentUID string
	if err := tx.QueryRowContext(ctx, `SELECT card FROM catdex_inventory WHERE user_id=$1 AND card_id=$2 AND authoritative FOR UPDATE`, uid, req.CardID).Scan(&aRaw); err == sql.ErrNoRows {
		return "", errNotFound
	} else if err != nil {
		return "", err
	}
	if err := tx.QueryRowContext(ctx, `SELECT user_id,card FROM catdex_inventory WHERE user_id<>$1 AND card_id=$2 AND authoritative FOR UPDATE`, uid, req.OpponentCardID).Scan(&opponentUID, &bRaw); err == sql.ErrNoRows {
		return "", errNotFound
	} else if err != nil {
		return "", err
	}
	var a, b Card
	if json.Unmarshal(aRaw, &a) != nil || json.Unmarshal(bRaw, &b) != nil {
		return "", fmt.Errorf("invalid stored fighter")
	}
	result := resolveBattle(toFighter(a), toFighter(b), uid+"\x00"+req.RequestID)
	battleID, err := newUUID()
	if err != nil {
		return "", err
	}
	result.BattleID = battleID
	raw, _ := json.Marshal(result)
	if _, err := tx.ExecContext(ctx, `INSERT INTO catdex_battles(id,user_id,request_id,opponent_user_id,result) VALUES($1,$2,$3,$4,$5)`,
		battleID, uid, req.RequestID, opponentUID, raw); err != nil {
		return "", err
	}
	aWon := result.WinnerID == a.ID
	aKey := map[bool]string{true: "wins", false: "losses"}[aWon]
	bKey := map[bool]string{true: "losses", false: "wins"}[aWon]
	if _, err := tx.ExecContext(ctx, `UPDATE catdex_inventory SET card=jsonb_set(card,ARRAY[$3]::text[],to_jsonb(COALESCE((card->>$3)::int,0)+1)),updated_at=now()
		WHERE user_id=$1 AND card_id=$2`, uid, a.ID, aKey); err != nil {
		return "", err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE catdex_inventory SET card=jsonb_set(card,ARRAY[$3]::text[],to_jsonb(COALESCE((card->>$3)::int,0)+1)),updated_at=now()
		WHERE user_id=$1 AND card_id=$2`, opponentUID, b.ID, bKey); err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", errConflict
	}
	return string(raw), nil
}

func toFighter(c Card) BattleFighter {
	return BattleFighter{ID: c.ID, Name: c.Name, Stars: c.Stars, Attack: c.Stats.Attack, Defense: c.Stats.Defense, Speed: c.Stats.Speed, Ability: c.Stats.Ability}
}
