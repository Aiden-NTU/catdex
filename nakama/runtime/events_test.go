package main

import (
	"fmt"
	"sync"
	"testing"
)

// This reference ledger mirrors the transactional cap ordering in
// rpcContributeEvent. It deliberately starts 100 contributors together and
// verifies the invariant independent of goroutine scheduling.
func TestHundredContributorEventCapIsDeterministic(t *testing.T) {
	type ledger struct {
		sync.Mutex
		progress int
		requests map[string]int
		users    map[string]int
	}
	run := func() (int, int) {
		state := ledger{requests: map[string]int{}, users: map[string]int{}}
		var wg sync.WaitGroup
		start := make(chan struct{})
		for i := 0; i < 100; i++ {
			wg.Add(1)
			go func(index int) {
				defer wg.Done()
				<-start
				user := fmt.Sprintf("user-%03d", index)
				request := "request-" + user
				for replay := 0; replay < 2; replay++ {
					state.Lock()
					if _, exists := state.requests[request]; !exists {
						accepted := min(3, min(250-state.progress, 5-state.users[user]))
						if accepted > 0 {
							state.progress += accepted
							state.users[user] += accepted
							state.requests[request] = accepted
						}
					}
					state.Unlock()
				}
			}(i)
		}
		close(start)
		wg.Wait()
		total := 0
		for _, amount := range state.requests {
			total += amount
		}
		return state.progress, total
	}
	for attempt := 0; attempt < 20; attempt++ {
		progress, ledgerTotal := run()
		if progress != 250 || ledgerTotal != 250 {
			t.Fatalf("attempt %d: progress=%d ledger=%d, want 250", attempt, progress, ledgerTotal)
		}
	}
}

func TestEventTemplateEligibility(t *testing.T) {
	tests := []struct {
		kind string
		req  contributionRequest
		meta map[string]any
		ok   bool
	}{
		{"cat_cafe_rally", contributionRequest{Type: "feed"}, nil, true},
		{"cat_cafe_rally", contributionRequest{Type: "squad"}, nil, false},
		{"cardboard_fortress", contributionRequest{Type: "squad", SquadID: "local"}, nil, true},
		{"laser_pointer_chase", contributionRequest{Type: "checkpoint", Checkpoint: "walk"},
			map[string]any{"checkpoints": []any{map[string]any{"id": "walk", "stationary": false}}}, true},
		{"laser_pointer_chase", contributionRequest{Type: "checkpoint", Checkpoint: "still", Stationary: true},
			map[string]any{"checkpoints": []any{map[string]any{"id": "still", "stationary": true}}}, true},
	}
	for _, test := range tests {
		got := validateEventContribution(test.kind, test.req, test.meta) == nil
		if got != test.ok {
			t.Errorf("%s request %+v: got %v, want %v", test.kind, test.req, got, test.ok)
		}
	}
}
