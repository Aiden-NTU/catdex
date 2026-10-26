package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

const battleTurnDuration = 30 * time.Second

type tacticalFighter struct {
	UserID   string `json:"userId"`
	CardID   string `json:"cardId"`
	Name     string `json:"name"`
	Attack   int    `json:"attack"`
	Defense  int    `json:"defense"`
	Speed    int    `json:"speed"`
	Ability  string `json:"ability"`
	HP       int    `json:"hp"`
	Energy   int    `json:"energy"`
	Guarding bool   `json:"guarding"`
}

type tacticalEvent struct {
	Sequence    int    `json:"sequence"`
	ActorCardID string `json:"actorCardId"`
	Action      string `json:"action"`
	Damage      int    `json:"damage"`
	TargetHP    int    `json:"targetHp"`
}

type tacticalBattle struct {
	MatchID                  string            `json:"matchId"`
	Revision                 int               `json:"revision"`
	TurnUserID               string            `json:"turnUserId"`
	TurnDeadline             time.Time         `json:"turnDeadline"`
	Fighters                 []tacticalFighter `json:"fighters"`
	Events                   []tacticalEvent   `json:"events"`
	Status                   string            `json:"status"`
	WinnerUserID             string            `json:"winnerUserId,omitempty"`
	LocalDevelopmentOpponent bool              `json:"localDevelopmentOpponent"`
}

type startBattleRequest struct {
	RequestID                string `json:"requestId"`
	CardID                   string `json:"cardId"`
	OpponentCardID           string `json:"opponentCardId"`
	LocalDevelopmentOpponent bool   `json:"localDevelopmentOpponent"`
}

func rpcBattleStart(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req startBattleRequest
	if decodeJSON(payload, &req) != nil || req.RequestID == "" || len(req.RequestID) > 128 ||
		req.CardID == "" || req.OpponentCardID == "" || req.CardID == req.OpponentCardID {
		return "", errInvalidArgument
	}
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	var prior []byte
	err = tx.QueryRowContext(ctx, `SELECT state FROM catdex_battle_matches WHERE creator_user_id=$1 AND request_id=$2`,
		uid, req.RequestID).Scan(&prior)
	if err == nil {
		return string(prior), nil
	}
	if err != sql.ErrNoRows {
		return "", err
	}
	var aRaw, bRaw []byte
	var opponentUID string
	if err := tx.QueryRowContext(ctx, `SELECT card FROM catdex_inventory
		WHERE user_id=$1 AND card_id=$2 AND authoritative`, uid, req.CardID).Scan(&aRaw); err == sql.ErrNoRows {
		return "", errNotFound
	} else if err != nil {
		return "", err
	}
	if err := tx.QueryRowContext(ctx, `SELECT user_id,card FROM catdex_inventory
		WHERE user_id<>$1 AND card_id=$2 AND authoritative`, uid, req.OpponentCardID).
		Scan(&opponentUID, &bRaw); err == sql.ErrNoRows {
		return "", errNotFound
	} else if err != nil {
		return "", err
	}
	var a, b Card
	if json.Unmarshal(aRaw, &a) != nil || json.Unmarshal(bRaw, &b) != nil {
		return "", errInvalidArgument
	}
	matchID, err := newUUID()
	if err != nil {
		return "", err
	}
	first := uid
	if b.Stats.Speed > a.Stats.Speed || (b.Stats.Speed == a.Stats.Speed && opponentUID < uid) {
		first = opponentUID
	}
	state := tacticalBattle{
		MatchID: matchID, TurnUserID: first, TurnDeadline: time.Now().UTC().Add(battleTurnDuration),
		Status: "active", Events: []tacticalEvent{},
		Fighters: []tacticalFighter{
			tacticalFromCard(uid, a),
			tacticalFromCard(opponentUID, b),
		},
	}
	raw, _ := json.Marshal(state)
	if _, err := tx.ExecContext(ctx, `INSERT INTO catdex_battle_matches
		(id,creator_user_id,request_id,player_a_user_id,player_b_user_id,state)
		VALUES($1,$2,$3,$2,$4,$5)`, matchID, uid, req.RequestID, opponentUID, raw); err != nil {
		return "", errConflict
	}
	if err := tx.Commit(); err != nil {
		return "", errConflict
	}
	return string(raw), nil
}

func rpcBattleGet(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req struct {
		MatchID string `json:"matchId"`
		CardID  string `json:"cardId"`
	}
	if decodeJSON(payload, &req) != nil || (req.MatchID == "" && req.CardID == "") {
		return "", errInvalidArgument
	}
	var raw []byte
	err = db.QueryRowContext(ctx, `SELECT state FROM catdex_battle_matches
		WHERE (id::text=$2::text OR ($2::text='' AND state->'fighters' @>
			jsonb_build_array(jsonb_build_object('cardId',$3::text))))
		AND (player_a_user_id=$1 OR player_b_user_id=$1)
		ORDER BY updated_at DESC LIMIT 1`, uid, req.MatchID, req.CardID).Scan(&raw)
	if err == sql.ErrNoRows {
		return "", errNotFound
	}
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

type tacticalActionRequest struct {
	RequestID        string `json:"requestId"`
	MatchID          string `json:"matchId"`
	ExpectedRevision int    `json:"expectedRevision"`
	Action           string `json:"action"`
}

func rpcBattleAction(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req tacticalActionRequest
	if decodeJSON(payload, &req) != nil || req.RequestID == "" || req.MatchID == "" ||
		(req.Action != "attack" && req.Action != "ability" && req.Action != "guard" && req.Action != "surrender") {
		return "", errInvalidArgument
	}
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	var replay []byte
	err = tx.QueryRowContext(ctx, `SELECT a.response FROM catdex_battle_action_ids a
		JOIN catdex_battle_matches m ON m.id=a.match_id
		WHERE a.match_id=$1 AND a.request_id=$2
		AND (m.player_a_user_id=$3 OR m.player_b_user_id=$3)`,
		req.MatchID, req.RequestID, uid).Scan(&replay)
	if err == nil {
		return string(replay), nil
	}
	if err != sql.ErrNoRows {
		return "", err
	}
	var raw []byte
	err = tx.QueryRowContext(ctx, `SELECT state FROM catdex_battle_matches WHERE id=$1
		AND (player_a_user_id=$2 OR player_b_user_id=$2) FOR UPDATE`, req.MatchID, uid).Scan(&raw)
	if err == sql.ErrNoRows {
		return "", errNotFound
	}
	if err != nil {
		return "", err
	}
	var state tacticalBattle
	if json.Unmarshal(raw, &state) != nil || state.Status != "active" {
		return "", errConflict
	}
	if state.Revision != req.ExpectedRevision {
		return "", errConflict
	}
	if time.Now().UTC().After(state.TurnDeadline) {
		if err := applyTacticalAction(&state, state.TurnUserID, "guard"); err != nil {
			return "", err
		}
		// A waiting opponent may submit immediately after the timer expires.
		// The server records the timed-out guard first, then their action.
		if state.TurnUserID != uid {
			req.Action = ""
		}
	} else if state.TurnUserID != uid {
		return "", errConflict
	}
	if req.Action != "" {
		if err := applyTacticalAction(&state, uid, req.Action); err != nil {
			return "", err
		}
	}
	if state.Status != "active" {
		for _, fighter := range state.Fighters {
			resultKey := "losses"
			if fighter.UserID == state.WinnerUserID {
				resultKey = "wins"
			}
			if _, err := tx.ExecContext(ctx, `UPDATE catdex_inventory SET
				card=jsonb_set(card,ARRAY[$3]::text[],
					to_jsonb(COALESCE((card->>$3)::int,0)+1)),updated_at=now()
				WHERE user_id=$1 AND card_id=$2`,
				fighter.UserID, fighter.CardID, resultKey); err != nil {
				return "", err
			}
		}
	}
	raw, _ = json.Marshal(state)
	result, err := tx.ExecContext(ctx, `UPDATE catdex_battle_matches SET state=$2,updated_at=now()
		WHERE id=$1 AND NOT EXISTS (SELECT 1 FROM catdex_battle_action_ids WHERE match_id=$1 AND request_id=$3)`,
		req.MatchID, raw, req.RequestID)
	if err != nil {
		return "", err
	}
	affected, _ := result.RowsAffected()
	if affected == 0 {
		var prior []byte
		if err := tx.QueryRowContext(ctx, `SELECT response FROM catdex_battle_action_ids
			WHERE match_id=$1 AND request_id=$2`, req.MatchID, req.RequestID).Scan(&prior); err != nil {
			return "", errConflict
		}
		return string(prior), nil
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO catdex_battle_action_ids(match_id,request_id,response)
		VALUES($1,$2,$3)`, req.MatchID, req.RequestID, raw); err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", errConflict
	}
	return string(raw), nil
}

func applyTacticalAction(state *tacticalBattle, uid, action string) error {
	actorIndex := -1
	for i := range state.Fighters {
		if state.Fighters[i].UserID == uid {
			actorIndex = i
		}
	}
	if actorIndex < 0 {
		return errNotFound
	}
	targetIndex := 1 - actorIndex
	actor, target := &state.Fighters[actorIndex], &state.Fighters[targetIndex]
	if action == "ability" && actor.Energy < 60 {
		return runtime.NewError("not enough energy", 9)
	}
	damage := 0
	switch action {
	case "surrender":
		state.Status, state.WinnerUserID = "surrendered", target.UserID
	case "guard":
		actor.Guarding = true
		actor.Energy = min(100, actor.Energy+25)
	default:
		damage = tacticalDamage(state.MatchID, state.Revision+1, *actor, *target, action)
		target.HP = max(0, target.HP-damage)
		target.Guarding = false
		actor.Guarding = false
		if action == "ability" {
			actor.Energy -= 60
		} else {
			actor.Energy = min(100, actor.Energy+20)
		}
		if target.HP == 0 {
			state.Status, state.WinnerUserID = "complete", actor.UserID
		}
	}
	state.Revision++
	state.Events = append(state.Events, tacticalEvent{
		Sequence: state.Revision, ActorCardID: actor.CardID, Action: action, Damage: damage, TargetHP: target.HP,
	})
	if state.Status == "active" {
		state.TurnUserID = target.UserID
		state.TurnDeadline = time.Now().UTC().Add(battleTurnDuration)
	}
	return nil
}

func tacticalDamage(seed string, sequence int, actor, target tacticalFighter, action string) int {
	multiplier := 100
	if action == "ability" {
		multiplier = 135
	}
	digest := sha256.Sum256([]byte(seed + "\x00" + itoa(sequence) + "\x00" + actor.CardID + "\x00" + action))
	variation := int(digest[0]%7) - 3
	damage := actor.Attack*multiplier/100 - target.Defense*35/100 + variation
	damage = min(40, max(4, damage))
	if target.Guarding {
		damage = min(40, max(2, (damage*55+50)/100))
	}
	return damage
}

func tacticalFromCard(uid string, card Card) tacticalFighter {
	return tacticalFighter{
		UserID: uid, CardID: card.ID, Name: card.Name, Attack: card.Stats.Attack,
		Defense: card.Stats.Defense, Speed: card.Stats.Speed, Ability: card.Stats.Ability, HP: 100,
	}
}

func itoa(value int) string {
	if value == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for value > 0 {
		i--
		buf[i] = byte('0' + value%10)
		value /= 10
	}
	return string(buf[i:])
}
