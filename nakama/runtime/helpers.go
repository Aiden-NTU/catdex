package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"strings"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

var (
	errUnauthenticated = runtime.NewError("authentication required", 16)
	errInvalidArgument = runtime.NewError("invalid argument", 3)
	errNotFound        = runtime.NewError("not found", 5)
	errConflict        = runtime.NewError("conflict", 10)
	errCooldown        = runtime.NewError("enrollment cooldown active", 9)
)

func decodeJSON[T any](payload string, dst *T) error {
	if strings.TrimSpace(payload) == "" {
		payload = "{}"
	}
	dec := json.NewDecoder(bytes.NewBufferString(payload))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return fmt.Errorf("invalid JSON: %w", err)
	}
	var trailing any
	if err := dec.Decode(&trailing); !errors.Is(err, io.EOF) {
		return errors.New("invalid JSON: trailing data")
	}
	return nil
}

func encodeJSON(v any) (string, error) {
	b, err := json.Marshal(v)
	if err != nil {
		return "", fmt.Errorf("encode response: %w", err)
	}
	return string(b), nil
}

func userID(ctx context.Context) (string, error) {
	id, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || id == "" {
		return "", errUnauthenticated
	}
	return id, nil
}

// validateCard normalizes the bounded fields accepted by inventory and enrollment.
func validateCard(c *Card) error {
	c.ID = strings.TrimSpace(c.ID)
	c.Name = strings.TrimSpace(c.Name)
	c.Breed = strings.TrimSpace(c.Breed)
	if c.ID == "" || len(c.ID) > 128 || c.Breed == "" || len(c.Breed) > 100 {
		return errInvalidArgument
	}
	if len(c.Name) > 100 || len(c.H3Cell) > 32 || c.Stars < 0 || c.Stars > 5 {
		return errInvalidArgument
	}
	if c.Stats.Attack < 0 || c.Stats.Attack > 250 || c.Stats.Defense < 0 || c.Stats.Defense > 250 ||
		c.Stats.Speed < 0 || c.Stats.Speed > 250 {
		return errInvalidArgument
	}
	return nil
}

func deterministicStars(secret, fingerprint, cell, day string) int {
	sum := sha256.Sum256([]byte(secret + "\x00" + fingerprint + "\x00" + cell + "\x00" + day))
	r := float64(binary.BigEndian.Uint64(sum[:8])) / float64(math.MaxUint64)
	switch {
	case r < .40:
		return 1
	case r < .70:
		return 2
	case r < .88:
		return 3
	case r < .97:
		return 4
	default:
		return 5
	}
}

func scaleStat(v, stars int) int {
	return int(math.Round(float64(v) * (1 + .12*float64(stars-1))))
}

func utcDay(t time.Time) string { return t.UTC().Format("2006-01-02") }

func newUUID() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:16]), nil
}
