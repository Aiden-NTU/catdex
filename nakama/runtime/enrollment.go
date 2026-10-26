package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
	h3 "github.com/uber/h3-go/v4"
)

const h3Resolution = 9

type enrollRequest struct {
	RequestID       string  `json:"requestId"`
	Fingerprint     string  `json:"fingerprint"`
	Name            string  `json:"name"`
	Breed           string  `json:"breed"`
	BreedConfidence float64 `json:"breedConfidence"`
	H3Cell          string  `json:"h3Cell"`
	Lat             float64 `json:"lat"`
	Lng             float64 `json:"lng"`
	AccuracyM       float64 `json:"accuracyM"`
	CapturedAt      string  `json:"capturedAt"`
	BaseAttack      int     `json:"baseAttack"`
	BaseDefense     int     `json:"baseDefense"`
	BaseSpeed       int     `json:"baseSpeed"`
	Ability         string  `json:"ability,omitempty"`
	AccentColor     string  `json:"accentColor,omitempty"`
}

type enrollResponse struct {
	Card       Card     `json:"card"`
	Idempotent bool     `json:"idempotent"`
	AuditFlags []string `json:"auditFlags,omitempty"`
}

func rpcEnroll(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	uid, err := userID(ctx)
	if err != nil {
		return "", err
	}
	var req enrollRequest
	if err := decodeJSON(payload, &req); err != nil {
		return "", invalid(err)
	}
	req.RequestID = strings.TrimSpace(req.RequestID)
	req.Fingerprint = strings.TrimSpace(req.Fingerprint)
	req.H3Cell = strings.TrimSpace(req.H3Cell)
	if req.RequestID == "" || len(req.RequestID) > 128 || req.Fingerprint == "" || len(req.Fingerprint) > 4096 ||
		req.H3Cell == "" || len(req.H3Cell) > 32 || req.Breed == "" || len(req.Breed) > 100 ||
		req.Lat < -90 || req.Lat > 90 || req.Lng < -180 || req.Lng > 180 ||
		math.IsNaN(req.Lat) || math.IsNaN(req.Lng) || math.IsNaN(req.AccuracyM) ||
		math.IsInf(req.Lat, 0) || math.IsInf(req.Lng, 0) || math.IsInf(req.AccuracyM, 0) || req.AccuracyM < 0 ||
		req.BaseAttack < 1 || req.BaseAttack > 150 || req.BaseDefense < 1 || req.BaseDefense > 150 ||
		req.BaseSpeed < 1 || req.BaseSpeed > 150 || req.BreedConfidence < 0 || req.BreedConfidence > 1 {
		return "", errInvalidArgument
	}
	capturedAt, err := time.Parse(time.RFC3339, req.CapturedAt)
	if err != nil {
		return "", invalid(fmt.Errorf("capturedAt must be RFC3339: %w", err))
	}
	fpSum := sha256.Sum256([]byte(req.Fingerprint))
	fingerprint := hex.EncodeToString(fpSum[:])
	now := time.Now().UTC()
	day := utcDay(now)
	cooldown := enrollmentCooldown()

	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, uid); err != nil {
		return "", err
	}
	var prior []byte
	err = tx.QueryRowContext(ctx, `SELECT response FROM catdex_enrollments WHERE user_id=$1 AND request_id=$2`, uid, req.RequestID).Scan(&prior)
	if err == nil {
		var out enrollResponse
		if json.Unmarshal(prior, &out) == nil {
			out.Idempotent = true
			return encodeJSON(out)
		}
		return string(prior), nil
	}
	if err != sql.ErrNoRows {
		return "", err
	}
	if req.AccuracyM > maxEnrollmentAccuracyM() {
		return "", runtime.NewError("location accuracy is too low", 3)
	}
	if capturedAt.After(now.Add(30*time.Second)) || now.Sub(capturedAt) > maxEnrollmentStaleness() {
		return "", runtime.NewError("location fix is stale", 3)
	}
	cell, err := h3.LatLngToCell(h3.NewLatLng(req.Lat, req.Lng), h3Resolution)
	if err != nil {
		return "", invalid(fmt.Errorf("invalid location: %w", err))
	}
	authoritativeCell := cell.String()
	if req.H3Cell != authoritativeCell {
		logger.Warn("enroll geo mismatch user=%s supplied=%s authoritative=%s", uid, req.H3Cell, authoritativeCell)
		return "", runtime.NewError("location cell mismatch", 3)
	}
	err = tx.QueryRowContext(ctx, `SELECT response FROM catdex_enrollments WHERE user_id=$1 AND fingerprint=$2 AND day_bucket=$3`, uid, fingerprint, day).Scan(&prior)
	if err == nil {
		var out enrollResponse
		if json.Unmarshal(prior, &out) == nil {
			out.Idempotent = true
			return encodeJSON(out)
		}
		return string(prior), nil
	}
	if err != sql.ErrNoRows {
		return "", err
	}
	var dailyCount int
	if err := tx.QueryRowContext(ctx, `SELECT count(*) FROM catdex_enrollments WHERE user_id=$1 AND day_bucket=$2`, uid, day).Scan(&dailyCount); err != nil {
		return "", err
	}
	if dailyCount >= maxDailyEnrollments() {
		return "", runtime.NewError("daily enrollment limit reached", 8)
	}
	var lastCellEnrollment time.Time
	err = tx.QueryRowContext(ctx, `SELECT created_at FROM catdex_enrollments WHERE user_id=$1 AND h3_cell=$2 ORDER BY created_at DESC LIMIT 1`, uid, authoritativeCell).Scan(&lastCellEnrollment)
	if err != nil && err != sql.ErrNoRows {
		return "", err
	}
	if err == nil && now.Sub(lastCellEnrollment) < cooldown {
		return "", runtime.NewError(fmt.Sprintf("cell enrollment cooldown active; retry in %d seconds", int((cooldown-now.Sub(lastCellEnrollment)).Seconds())+1), 9)
	}
	auditFlags := []string{}
	var lastLat, lastLng float64
	var lastCaptured time.Time
	err = tx.QueryRowContext(ctx, `SELECT lat,lng,captured_at FROM catdex_enrollments
		WHERE user_id=$1 AND captured_at IS NOT NULL ORDER BY captured_at DESC LIMIT 1`, uid).Scan(&lastLat, &lastLng, &lastCaptured)
	if err != nil && err != sql.ErrNoRows {
		return "", err
	}
	if err == nil {
		speedKmh := travelSpeedKmh(lastLat, lastLng, lastCaptured, req.Lat, req.Lng, capturedAt)
		if speedKmh > impossibleTravelKmh() {
			logger.Warn("impossible travel user=%s speed_kmh=%.1f", uid, speedKmh)
			return "", runtime.NewError("location change is not physically plausible", 3)
		}
		if speedKmh > impossibleTravelKmh()/2 {
			auditFlags = append(auditFlags, "high_velocity")
		}
	}
	if req.AccuracyM > maxEnrollmentAccuracyM()*0.75 {
		auditFlags = append(auditFlags, "low_accuracy")
	}
	stars := deterministicStars(enrollmentSecret, fingerprint, authoritativeCell, day)
	stats := Stats{
		Attack: scaleStat(req.BaseAttack, stars), Defense: scaleStat(req.BaseDefense, stars),
		Speed: scaleStat(req.BaseSpeed, stars), Ability: req.Ability,
	}
	stats.BattlePower = stats.Attack + stats.Defense + stats.Speed
	cardID, err := newUUID()
	if err != nil {
		return "", err
	}
	card := Card{
		ID: cardID, Name: strings.TrimSpace(req.Name), Breed: strings.TrimSpace(req.Breed),
		BreedConfidence: req.BreedConfidence, CreatedAt: now.Format(time.RFC3339),
		Stats: stats, AccentColor: req.AccentColor, Stars: stars, H3Cell: authoritativeCell,
		Lat: &req.Lat, Lng: &req.Lng, Level: 1,
	}
	if card.Name == "" {
		card.Name = card.Breed
	}
	out := enrollResponse{Card: card, AuditFlags: auditFlags}
	cardJSON, _ := json.Marshal(card)
	responseJSON, _ := json.Marshal(out)
	if _, err := tx.ExecContext(ctx, `INSERT INTO catdex_inventory(user_id,card_id,card,authoritative,level,xp,base_stats) VALUES($1,$2,$3,true,1,0,$3::jsonb->'stats')`,
		uid, card.ID, cardJSON); err != nil {
		return "", err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO catdex_enrollments
		(user_id,request_id,fingerprint,day_bucket,card_id,response,h3_cell,lat,lng,accuracy_m,captured_at,audit_flags)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
		uid, req.RequestID, fingerprint, day, card.ID, responseJSON, authoritativeCell,
		req.Lat, req.Lng, req.AccuracyM, capturedAt, auditFlags); err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", errConflict
	}
	return string(responseJSON), nil
}

func enrollmentCooldown() time.Duration {
	seconds, err := strconv.Atoi(os.Getenv("CATDEX_ENROLLMENT_COOLDOWN_SECONDS"))
	if err != nil || seconds < 0 {
		seconds = 900
	}
	return time.Duration(seconds) * time.Second
}

func maxEnrollmentAccuracyM() float64 {
	return envFloat("CATDEX_MAX_ENROLLMENT_ACCURACY_M", 100)
}

func maxEnrollmentStaleness() time.Duration {
	return time.Duration(envInt("CATDEX_MAX_ENROLLMENT_STALENESS_SECONDS", 120)) * time.Second
}

func maxDailyEnrollments() int {
	return envInt("CATDEX_MAX_DAILY_ENROLLMENTS", 25)
}

func impossibleTravelKmh() float64 {
	return envFloat("CATDEX_IMPOSSIBLE_TRAVEL_KMH", 300)
}

func envInt(name string, fallback int) int {
	value, err := strconv.Atoi(os.Getenv(name))
	if err != nil || value <= 0 {
		return fallback
	}
	return value
}

func envFloat(name string, fallback float64) float64 {
	value, err := strconv.ParseFloat(os.Getenv(name), 64)
	if err != nil || value <= 0 {
		return fallback
	}
	return value
}

func travelSpeedKmh(lat1, lng1 float64, t1 time.Time, lat2, lng2 float64, t2 time.Time) float64 {
	elapsedHours := t2.Sub(t1).Hours()
	if elapsedHours <= 0 {
		if lat1 == lat2 && lng1 == lng2 {
			return 0
		}
		return math.Inf(1)
	}
	const earthRadiusKm = 6371
	toRadians := math.Pi / 180
	dLat := (lat2 - lat1) * toRadians
	dLng := (lng2 - lng1) * toRadians
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*toRadians)*math.Cos(lat2*toRadians)*math.Sin(dLng/2)*math.Sin(dLng/2)
	distanceKm := 2 * earthRadiusKm * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	return distanceKm / elapsedHours
}
