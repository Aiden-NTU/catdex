package main

import (
	"math"
	"strings"
	"testing"
	"time"

	h3 "github.com/uber/h3-go/v4"
)

func TestDecodeJSONStrict(t *testing.T) {
	var dst struct {
		Name string `json:"name"`
	}
	if err := decodeJSON(`{"name":"Miso"}`, &dst); err != nil || dst.Name != "Miso" {
		t.Fatalf("decode: name=%q err=%v", dst.Name, err)
	}
	if err := decodeJSON(`{"name":"Miso","admin":true}`, &dst); err == nil {
		t.Fatal("unknown field was accepted")
	}
	if err := decodeJSON(`{"name":"Miso"} {}`, &dst); err == nil {
		t.Fatal("trailing object was accepted")
	}
}

func TestEnrollmentH3ResolutionAndTravelThreshold(t *testing.T) {
	cell, err := h3.LatLngToCell(h3.NewLatLng(51.5074, -0.1278), h3Resolution)
	if err != nil {
		t.Fatalf("H3 conversion failed: %v", err)
	}
	if cell.Resolution() != h3Resolution {
		t.Fatalf("unexpected H3 resolution: %d", cell.Resolution())
	}
	start := time.Date(2026, 10, 26, 12, 0, 0, 0, time.UTC)
	walking := travelSpeedKmh(51.5074, -0.1278, start, 51.5084, -0.1278, start.Add(time.Minute))
	if walking < 5 || walking > 10 {
		t.Fatalf("unexpected walking speed: %.2f km/h", walking)
	}
	impossible := travelSpeedKmh(51.5074, -0.1278, start, 48.8566, 2.3522, start.Add(time.Minute))
	if impossible <= 300 {
		t.Fatalf("expected impossible travel, got %.2f km/h", impossible)
	}
	if !math.IsInf(travelSpeedKmh(0, 0, start, 1, 1, start), 1) {
		t.Fatal("different points at the same time must be impossible")
	}
}

func TestDeterministicStars(t *testing.T) {
	const secret = "01234567890123456789012345678901"
	got := deterministicStars(secret, "fingerprint", "cell", "2026-10-26")
	if got < 1 || got > 5 {
		t.Fatalf("stars out of range: %d", got)
	}
	if again := deterministicStars(secret, "fingerprint", "cell", "2026-10-26"); again != got {
		t.Fatalf("not deterministic: %d != %d", again, got)
	}
	if scaleStat(100, 5) != 148 {
		t.Fatalf("unexpected five-star scaling: %d", scaleStat(100, 5))
	}
}

func TestBattleIsDeterministicAndBounded(t *testing.T) {
	a := BattleFighter{ID: "a", Name: "A", Stars: 3, Attack: 75, Defense: 62, Speed: 80}
	b := BattleFighter{ID: "b", Name: "B", Stars: 2, Attack: 70, Defense: 72, Speed: 55}
	first := resolveBattle(a, b, "request-1")
	second := resolveBattle(a, b, "request-1")
	if first.WinnerID != second.WinnerID || first.Seed != second.Seed || len(first.Log) != len(second.Log) {
		t.Fatalf("battle is not deterministic: %#v %#v", first, second)
	}
	if first.Turns < 1 || first.Turns > 12 {
		t.Fatalf("turn count out of range: %d", first.Turns)
	}
	if first.WinnerID != "a" && first.WinnerID != "b" {
		t.Fatalf("unknown winner: %q", first.WinnerID)
	}
}

func TestTacticalBattleGoldenVectors(t *testing.T) {
	actor := tacticalFighter{CardID: "miso", Attack: 45, Defense: 40}
	target := tacticalFighter{CardID: "bean", Attack: 40, Defense: 50}
	if got := tacticalDamage("golden", 1, actor, target, "attack"); got != 26 {
		t.Fatalf("attack golden vector=%d, want 26", got)
	}
	if got := tacticalDamage("golden", 2, actor, target, "ability"); got != 40 {
		t.Fatalf("ability golden vector=%d, want 40", got)
	}
	target.Guarding = true
	if got := tacticalDamage("golden", 1, actor, target, "attack"); got != 14 {
		t.Fatalf("guarded golden vector=%d, want 14", got)
	}
}

func TestTacticalActionsValidateEnergyAndAdvanceTurn(t *testing.T) {
	state := tacticalBattle{
		MatchID: "golden", Status: "active", TurnUserID: "u1",
		Fighters: []tacticalFighter{
			{UserID: "u1", CardID: "miso", Attack: 45, Defense: 40, HP: 100},
			{UserID: "u2", CardID: "bean", Attack: 40, Defense: 50, HP: 100},
		},
	}
	if err := applyTacticalAction(&state, "u1", "ability"); err == nil {
		t.Fatal("ability without energy was accepted")
	}
	if err := applyTacticalAction(&state, "u1", "attack"); err != nil {
		t.Fatalf("attack rejected: %v", err)
	}
	if state.Revision != 1 || state.TurnUserID != "u2" || len(state.Events) != 1 {
		t.Fatalf("turn did not advance: %+v", state)
	}
	if err := applyTacticalAction(&state, "u2", "guard"); err != nil {
		t.Fatalf("guard rejected: %v", err)
	}
	if !state.Fighters[1].Guarding || state.Fighters[1].Energy != 25 {
		t.Fatalf("guard state incorrect: %+v", state.Fighters[1])
	}
}

func TestValidateCardBounds(t *testing.T) {
	card := Card{ID: "id", Breed: "Mixed", Stars: 6}
	if err := validateCard(&card); err == nil {
		t.Fatal("accepted invalid stars")
	}
	card.Stars = 1
	card.ID = strings.Repeat("x", 129)
	if err := validateCard(&card); err == nil {
		t.Fatal("accepted oversized id")
	}
}

func TestCatLevelThresholdsAndDerivedStats(t *testing.T) {
	for level := 1; level <= maxCatLevel; level++ {
		xp := totalXPForLevel(level)
		if got := levelForXP(xp); got != level {
			t.Fatalf("levelForXP(%d)=%d, want %d", xp, got, level)
		}
		if level > 1 && levelForXP(xp-1) != level-1 {
			t.Fatalf("xp immediately below level %d crossed threshold", level)
		}
	}
	card := Card{Level: 10, AbilityMastery: 50, Stats: Stats{Attack: 100, Defense: 80, Speed: 60}}
	deriveBattleStats(&card)
	if card.Stats.Attack != 119 || card.Stats.BattlePower != 285 {
		t.Fatalf("unexpected derived stats: %+v", card.Stats)
	}
}

func TestCareRulesAreBoundedAndRequireResources(t *testing.T) {
	for name, rule := range careRules {
		if rule.cooldown < 15*time.Minute {
			t.Errorf("%s cooldown too short: %s", name, rule.cooldown)
		}
		if rule.xp < 0 || rule.xp > 30 || rule.coins < 0 || rule.coins > 4 {
			t.Errorf("%s has unbounded reward: %+v", name, rule)
		}
		if rule.energy < -20 || rule.energy > 30 || rule.hunger > 20 ||
			rule.mood > 15 || rule.bond > 12 || rule.mastery > 10 {
			t.Errorf("%s has unbounded meter delta: %+v", name, rule)
		}
	}
	if careRules["feed"].treats != -1 || careRules["groom"].grooming != -1 {
		t.Fatal("consumable care actions must debit inventory")
	}
}

func TestDeterministicNinetyDayEconomySimulation(t *testing.T) {
	type snapshot struct {
		coins, earned, treats, grooming, xp int
		energy, hunger, mood, bond, mastery int
	}
	simulate := func() snapshot {
		s := snapshot{treats: 5, grooming: 3, energy: 100, hunger: 40, mood: 75}
		for day := 0; day < 90; day++ {
			s.earned = 0
			if day > 0 {
				s.treats = min(20, s.treats+3)
				s.grooming = min(10, s.grooming+1)
			}
			// This fixed schedule stays below every action cooldown and models
			// one morning/evening care session without any neglect decay.
			for _, action := range []string{"feed", "play", "train", "rest", "play", "groom"} {
				r := careRules[action]
				if s.treats+r.treats < 0 || s.grooming+r.grooming < 0 || s.energy+r.energy < 0 {
					continue
				}
				s.energy = clamp(s.energy+r.energy, 0, 100)
				s.hunger = clamp(s.hunger+r.hunger, 0, 100)
				s.mood = clamp(s.mood+r.mood, 0, 100)
				s.bond = clamp(s.bond+r.bond, 0, 100)
				s.mastery = clamp(s.mastery+r.mastery, 0, 100)
				s.treats += r.treats
				s.grooming += r.grooming
				award := min(r.coins, dailyCoinCap-s.earned)
				s.coins += award
				s.earned += award
				s.xp = min(totalXPForLevel(maxCatLevel), s.xp+r.xp)
			}
			if s.earned < 0 || s.earned > dailyCoinCap || s.treats < 0 || s.grooming < 0 ||
				s.energy < 0 || s.energy > 100 || s.hunger < 0 || s.hunger > 100 ||
				s.mood < 0 || s.mood > 100 || s.bond < 0 || s.bond > 100 ||
				s.mastery < 0 || s.mastery > 100 {
				t.Fatalf("out-of-bounds day %d: %+v", day, s)
			}
		}
		return s
	}
	first, second := simulate(), simulate()
	if first != second {
		t.Fatalf("simulation is not deterministic: %+v != %+v", first, second)
	}
	if first.coins <= 0 || first.xp <= 0 || levelForXP(first.xp) > maxCatLevel {
		t.Fatalf("invalid 90-day outcome: %+v", first)
	}
}
