package main

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"math/rand"
)

type fighterState struct {
	BattleFighter
	hp          int
	abilityUsed bool
	defending   bool
}

func resolveBattle(a, b BattleFighter, nonce string) BattleResult {
	ids := a.ID + "\x00" + b.ID
	seedBytes := sha256.Sum256([]byte(ids + "\x00" + nonce))
	seedLabel := hex.EncodeToString(seedBytes[:8])
	rng := rand.New(rand.NewSource(int64(binary.BigEndian.Uint64(seedBytes[:8]))))
	fa := fighterState{BattleFighter: a, hp: 100}
	fb := fighterState{BattleFighter: b, hp: 100}
	logs := make([]BattleLog, 0, 24)

	for turn := 1; turn <= 12 && fa.hp > 0 && fb.hp > 0; turn++ {
		first, second := &fa, &fb
		if fb.Speed > fa.Speed || (fb.Speed == fa.Speed && fb.ID < fa.ID) {
			first, second = second, first
		}
		takeTurn(first, second, turn, rng, &logs)
		if second.hp > 0 {
			takeTurn(second, first, turn, rng, &logs)
		}
	}
	winner := &fa
	if fb.hp > fa.hp || (fb.hp == fa.hp && fb.ID < fa.ID) {
		winner = &fb
	}
	turns := 0
	if len(logs) > 0 {
		turns = logs[len(logs)-1].Turn
	}
	return BattleResult{WinnerID: winner.ID, Turns: turns, Seed: seedLabel, Log: logs}
}

func takeTurn(actor, target *fighterState, turn int, rng *rand.Rand, logs *[]BattleLog) {
	actor.defending = false
	if !actor.abilityUsed && actor.hp < 55 && rng.Float64() < .55 {
		actor.abilityUsed = true
		damage := battleDamage(actor, target, 1.35+rng.Float64()*.25, rng)
		target.hp = max(0, target.hp-damage)
		*logs = append(*logs, BattleLog{Turn: turn, Actor: actor.ID, Action: "ability", Damage: damage, TargetHP: target.hp})
		return
	}
	if rng.Float64() < .18 {
		actor.defending = true
		*logs = append(*logs, BattleLog{Turn: turn, Actor: actor.ID, Action: "defend", TargetHP: target.hp})
		return
	}
	damage := battleDamage(actor, target, 1, rng)
	target.hp = max(0, target.hp-damage)
	*logs = append(*logs, BattleLog{Turn: turn, Actor: actor.ID, Action: "attack", Damage: damage, TargetHP: target.hp})
}

func battleDamage(actor, target *fighterState, multiplier float64, rng *rand.Rand) int {
	damage := int(float64(actor.Attack)*multiplier - float64(target.Defense)*.35 + .5)
	damage = min(40, max(4, damage))
	if target.defending {
		damage = min(40, max(2, int(float64(damage)*.55+.5)))
	}
	if rng.Float64() < .08+float64(actor.Stars)*.01 {
		damage = int(float64(damage)*1.5 + .5)
	}
	return damage
}
