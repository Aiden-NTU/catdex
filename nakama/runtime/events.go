package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"os"
	"strconv"
	"time"

	h3 "github.com/uber/h3-go/v4"
)

// seedDevelopmentEvents creates a rolling, deterministic-looking fixture set
// only when explicitly enabled. Production operators use the audited seed
// script, while local stacks receive useful events after every fresh start.
func seedDevelopmentEvents(ctx context.Context, db *sql.DB) error {
	if os.Getenv("CATDEX_SEED_DEVELOPMENT_EVENTS") != "true" {
		return nil
	}
	lat := envSignedFloat("CATDEX_EVENT_SEED_LAT", 51.5074)
	lng := envSignedFloat("CATDEX_EVENT_SEED_LNG", -0.1278)
	cell, err := h3.LatLngToCell(h3.NewLatLng(lat, lng), h3Resolution)
	if err != nil {
		return err
	}
	centers := []struct {
		kind, title, description string
		goal, cap, radius        int
		metadata                 map[string]any
	}{
		{"cat_cafe_rally", "Cat Café Rally", "Pool treats to keep the neighborhood café bowls full.", 120, 12, 500, map[string]any{"resource": "treats"}},
		{"cardboard_fortress", "Cardboard Fortress", "Join a squad and reinforce the community fortress.", 200, 20, 550, map[string]any{"requiresSquad": true}},
		{"laser_pointer_chase", "Laser Pointer Chase", "Tag checkpoints, or use the stationary accessible checkpoint.", 100, 10, 600,
			map[string]any{"checkpoints": []map[string]any{
				{"id": "loop-a", "label": "Courtyard", "stationary": false},
				{"id": "accessible", "label": "Stationary beam", "stationary": true},
			}}},
	}
	start := time.Now().UTC().Truncate(time.Hour).Add(-10 * time.Minute)
	for i, fixture := range centers {
		id, err := newUUID()
		if err != nil {
			return err
		}
		raw, _ := json.Marshal(fixture.metadata)
		eventStart := start.Add(time.Duration(i) * 15 * time.Minute)
		_, err = db.ExecContext(ctx, `INSERT INTO catdex_events
			(id,h3_cell,kind,title,description,goal,starts_at,ends_at,radius_m,per_user_cap,
			 latitude,longitude,metadata,personal_reward,community_reward)
			SELECT $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,5,20
			WHERE NOT EXISTS (SELECT 1 FROM catdex_events WHERE kind=$3 AND ends_at>now())`,
			id, cell.String(), fixture.kind, fixture.title, fixture.description, fixture.goal,
			eventStart, eventStart.Add(2*time.Hour), fixture.radius, fixture.cap, lat, lng, raw)
		if err != nil {
			return err
		}
	}
	return nil
}

func envSignedFloat(name string, fallback float64) float64 {
	value, err := strconv.ParseFloat(os.Getenv(name), 64)
	if err != nil {
		return fallback
	}
	return value
}
