package main

import "time"

type Stats struct {
	Attack      int    `json:"attack"`
	Defense     int    `json:"defense"`
	Speed       int    `json:"speed"`
	BattlePower int    `json:"battlePower"`
	Ability     string `json:"ability,omitempty"`
}

type Card struct {
	ID                   string     `json:"id"`
	Name                 string     `json:"name"`
	Breed                string     `json:"breed"`
	BreedConfidence      float64    `json:"breedConfidence,omitempty"`
	CreatedAt            string     `json:"createdAt"`
	Stats                Stats      `json:"stats"`
	AccentColor          string     `json:"accentColor,omitempty"`
	Sticker              string     `json:"sticker,omitempty"`
	Stars                int        `json:"stars"`
	H3Cell               string     `json:"h3Cell,omitempty"`
	Lat                  *float64   `json:"lat,omitempty"`
	Lng                  *float64   `json:"lng,omitempty"`
	Wins                 int        `json:"wins"`
	Losses               int        `json:"losses"`
	Level                int        `json:"level,omitempty"`
	XP                   int        `json:"xp,omitempty"`
	Energy               int        `json:"energy"`
	Hunger               int        `json:"hunger"`
	Mood                 int        `json:"mood"`
	Bond                 int        `json:"bond"`
	AbilityMastery       int        `json:"abilityMastery"`
	LastFedAt            *time.Time `json:"lastFedAt,omitempty"`
	LastPlayedAt         *time.Time `json:"lastPlayedAt,omitempty"`
	LastGroomedAt        *time.Time `json:"lastGroomedAt,omitempty"`
	LastTrainedAt        *time.Time `json:"lastTrainedAt,omitempty"`
	LastRestedAt         *time.Time `json:"lastRestedAt,omitempty"`
	ProgressionUpdatedAt *time.Time `json:"progressionUpdatedAt,omitempty"`
}

type BattleFighter struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Stars   int    `json:"stars"`
	Attack  int    `json:"attack"`
	Defense int    `json:"defense"`
	Speed   int    `json:"speed"`
	Ability string `json:"ability,omitempty"`
}

type BattleLog struct {
	Turn     int    `json:"turn"`
	Actor    string `json:"actor"`
	Action   string `json:"action"`
	Damage   int    `json:"damage,omitempty"`
	TargetHP int    `json:"targetHp,omitempty"`
}

type BattleResult struct {
	BattleID string      `json:"battleId"`
	WinnerID string      `json:"winnerId"`
	Turns    int         `json:"turns"`
	Seed     string      `json:"seed"`
	Log      []BattleLog `json:"log"`
}

type nearbyEvent struct {
	ID             string         `json:"id"`
	H3Cell         string         `json:"h3Cell"`
	Kind           string         `json:"kind"`
	Title          string         `json:"title"`
	Description    string         `json:"description"`
	Goal           int            `json:"goal"`
	Progress       int            `json:"progress"`
	RadiusM        int            `json:"radiusM"`
	PerUserCap     int            `json:"perUserCap"`
	StartsAt       time.Time      `json:"startsAt"`
	EndsAt         time.Time      `json:"endsAt"`
	Latitude       float64        `json:"latitude"`
	Longitude      float64        `json:"longitude"`
	Metadata       map[string]any `json:"metadata"`
	MyContribution int            `json:"myContribution"`
	State          string         `json:"state"`
	RewardClaimed  bool           `json:"rewardClaimed"`
}
