package main

import (
	"context"
	"strings"
	"testing"

	"github.com/heroiclabs/nakama-common/runtime"
)

func TestVersionComparison(t *testing.T) {
	for _, tc := range []struct {
		left, right string
		want        int
	}{
		{"1.2.3", "1.2.3", 0},
		{"v2.0.0", "1.99.99", 1},
		{"1.3.0-beta", "1.2.9", 1},
		{"", "1.0.0", -1},
	} {
		if got := compareVersions(tc.left, tc.right); got != tc.want {
			t.Errorf("compareVersions(%q,%q)=%d want %d", tc.left, tc.right, got, tc.want)
		}
	}
}

func TestMinimumVersionGate(t *testing.T) {
	t.Setenv("CATDEX_MIN_CLIENT_VERSION", "2.3.0")
	t.Setenv("CATDEX_MIN_RULES_VERSION", "7")
	ctx := context.WithValue(context.Background(), runtime.RUNTIME_CTX_HEADERS, map[string][]string{
		"X-Catdex-Client-Version": {"2.3.1"},
		"X-Catdex-Rules-Version":  {"7"},
	})
	if !supportedClient(ctx) {
		t.Fatal("supported client rejected")
	}
	old := context.WithValue(context.Background(), runtime.RUNTIME_CTX_HEADERS, map[string][]string{
		"X-Catdex-Client-Version": {"2.2.9"},
		"X-Catdex-Rules-Version":  {"7"},
	})
	if supportedClient(old) {
		t.Fatal("obsolete client accepted")
	}
}

func TestFeatureKillSwitch(t *testing.T) {
	t.Setenv("CATDEX_FEATURE_BATTLE", "false")
	if featureEnabled("battle") {
		t.Fatal("disabled feature was enabled")
	}
	t.Setenv("CATDEX_FEATURE_BATTLE", "true")
	if !featureEnabled("battle") {
		t.Fatal("enabled feature was disabled")
	}
}

func TestAcceleratedDeterministicSeventyTwoHourSoak(t *testing.T) {
	type userState struct {
		requests, accepted, rejected int
		hash                         string
	}
	run := func() [100]userState {
		var users [100]userState
		// 72 virtual hours, sampled once per virtual minute for 100 users.
		for minute := 0; minute < 72*60; minute++ {
			for id := range users {
				users[id].requests++
				// Deterministic kill-switch windows and a 30/minute mutation cap.
				maintenance := minute >= 24*60 && minute < 24*60+15
				if maintenance || (minute+id)%97 == 0 {
					users[id].rejected++
				} else {
					users[id].accepted++
				}
				users[id].hash = auditIdentity(strings.Repeat(string(rune('a'+id%26)), 8))
			}
		}
		return users
	}
	first, second := run(), run()
	if first != second {
		t.Fatal("accelerated soak is not deterministic")
	}
	for id, state := range first {
		if state.requests != 72*60 || state.accepted+state.rejected != state.requests ||
			state.hash == "" || state.hash == "anonymous" {
			t.Fatalf("invalid user %d state: %+v", id, state)
		}
	}
}
