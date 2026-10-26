package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

const maxRPCPayloadBytes = 64 * 1024

type rpcHandler func(context.Context, runtime.Logger, *sql.DB, runtime.NakamaModule, string) (string, error)

type rpcPolicy struct {
	authenticated bool
	mutating      bool
	feature       string
	limit         int
}

var policies = map[string]rpcPolicy{
	"catdex_health":           {limit: 30},
	"catdex_bootstrap":        {authenticated: true, limit: 30},
	"catdex_get_inventory":    {authenticated: true, limit: 60},
	"catdex_upsert_inventory": {authenticated: true, mutating: true, feature: "inventory_writes", limit: 20},
	"catdex_enroll":           {authenticated: true, mutating: true, feature: "enrollment", limit: 10},
	"catdex_feed":             {authenticated: true, mutating: true, feature: "progression", limit: 30},
	"catdex_get_care_state":   {authenticated: true, limit: 60},
	"catdex_care_action":      {authenticated: true, mutating: true, feature: "progression", limit: 30},
	"catdex_nearby_events":    {authenticated: true, feature: "events", limit: 60},
	"catdex_contribute_event": {authenticated: true, mutating: true, feature: "events", limit: 30},
	"catdex_event_summary":    {authenticated: true, feature: "events", limit: 60},
	"catdex_get_opponent":     {authenticated: true, feature: "battle", limit: 30},
	"catdex_resolve_battle":   {authenticated: true, mutating: true, feature: "battle", limit: 20},
	"catdex_battle_start":     {authenticated: true, mutating: true, feature: "battle", limit: 20},
	"catdex_battle_get":       {authenticated: true, feature: "battle", limit: 60},
	"catdex_battle_action":    {authenticated: true, mutating: true, feature: "battle", limit: 60},
	"catdex_account_export":   {authenticated: true, feature: "account_tools", limit: 3},
	"catdex_account_delete":   {authenticated: true, mutating: true, feature: "account_tools", limit: 2},
	"catdex_admin_seed_event": {authenticated: true, mutating: true, feature: "event_admin", limit: 5},
	"catdex_admin_retention":  {authenticated: true, mutating: true, feature: "ops_maintenance", limit: 2},
}

func hardenRPC(name string, next rpcHandler) rpcHandler {
	policy := policies[name]
	return func(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (response string, returnedErr error) {
		if len(payload) > maxRPCPayloadBytes {
			return "", runtime.NewError("payload too large", 3)
		}
		uid, _ := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
		if policy.authenticated && uid == "" {
			return "", errUnauthenticated
		}
		if policy.feature != "" && !featureEnabled(policy.feature) {
			return "", runtime.NewError("feature temporarily unavailable", 14)
		}
		if name != "catdex_bootstrap" && !supportedClient(ctx) {
			return "", runtime.NewError("client update required", 9)
		}
		if err := consumeRate(ctx, db, uid, name, policy.limit); err != nil {
			if errors.Is(err, errRateLimited) {
				return "", runtime.NewError("rate limit exceeded", 8)
			}
			logger.Error("rpc guard failed rpc=%s user=%s error=%v", name, auditIdentity(uid), err)
			return "", runtime.NewError("service temporarily unavailable", 14)
		}

		started := time.Now()
		response, err := next(ctx, logger, db, nk, payload)
		if policy.mutating {
			outcome := "ok"
			if err != nil {
				outcome = "rejected"
			}
			if auditErr := appendAudit(ctx, db, uid, name, outcome, time.Since(started)); auditErr != nil {
				logger.Error("audit append failed rpc=%s user=%s error=%v", name, auditIdentity(uid), auditErr)
				if err == nil {
					return "", runtime.NewError("service temporarily unavailable", 14)
				}
			}
		}
		if err == nil {
			return response, nil
		}
		var public *runtime.Error
		if errors.As(err, &public) {
			return "", public
		}
		logger.Error("rpc failed rpc=%s user=%s error=%v", name, auditIdentity(uid), err)
		return "", runtime.NewError("request could not be completed", 13)
	}
}

var errRateLimited = errors.New("rate limited")

func consumeRate(ctx context.Context, db *sql.DB, uid, rpc string, limit int) error {
	if limit <= 0 {
		return nil
	}
	key := "user:" + uid
	if uid == "" {
		key = "anonymous"
	}
	if ip, ok := ctx.Value(runtime.RUNTIME_CTX_CLIENT_IP).(string); ok && ip != "" {
		sum := sha256.Sum256([]byte(enrollmentSecret + "\x00" + ip))
		key += ":ip:" + hex.EncodeToString(sum[:12])
	}
	var count int
	err := db.QueryRowContext(ctx, `INSERT INTO catdex_rpc_rate_limits(subject,rpc,window_start,hits)
		VALUES($1,$2,date_trunc('minute',now()),1)
		ON CONFLICT(subject,rpc,window_start) DO UPDATE SET hits=catdex_rpc_rate_limits.hits+1
		RETURNING hits`, key, rpc).Scan(&count)
	if err != nil {
		return err
	}
	if count > limit {
		return errRateLimited
	}
	return nil
}

func appendAudit(ctx context.Context, db *sql.DB, uid, action, outcome string, latency time.Duration) error {
	_, err := db.ExecContext(ctx, `INSERT INTO catdex_audit_ledger
		(actor_hash,action,outcome,request_id,latency_ms)
		VALUES($1,$2,$3,$4,$5)`,
		auditIdentity(uid), action, outcome, requestID(ctx), latency.Milliseconds())
	return err
}

func auditIdentity(value string) string {
	if value == "" {
		return "anonymous"
	}
	sum := sha256.Sum256([]byte(enrollmentSecret + "\x00audit\x00" + value))
	return hex.EncodeToString(sum[:16])
}

func requestID(ctx context.Context) string {
	headers, _ := ctx.Value(runtime.RUNTIME_CTX_HEADERS).(map[string][]string)
	for key, values := range headers {
		if strings.EqualFold(key, "x-request-id") && len(values) > 0 && len(values[0]) <= 128 {
			return values[0]
		}
	}
	return ""
}

func featureEnabled(name string) bool {
	key := "CATDEX_FEATURE_" + strings.ToUpper(name)
	value := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	return value != "false" && value != "0" && value != "off"
}

func supportedClient(ctx context.Context) bool {
	minClient := strings.TrimSpace(os.Getenv("CATDEX_MIN_CLIENT_VERSION"))
	minRules := strings.TrimSpace(os.Getenv("CATDEX_MIN_RULES_VERSION"))
	if minClient == "" && minRules == "" {
		return true
	}
	headers, _ := ctx.Value(runtime.RUNTIME_CTX_HEADERS).(map[string][]string)
	client := firstHeader(headers, "x-catdex-client-version")
	rules := firstHeader(headers, "x-catdex-rules-version")
	return (minClient == "" || compareVersions(client, minClient) >= 0) &&
		(minRules == "" || compareVersions(rules, minRules) >= 0)
}

func firstHeader(headers map[string][]string, wanted string) string {
	for key, values := range headers {
		if strings.EqualFold(key, wanted) && len(values) > 0 {
			return strings.TrimSpace(values[0])
		}
	}
	return ""
}

func compareVersions(left, right string) int {
	parse := func(value string) []int {
		parts := strings.Split(strings.TrimPrefix(value, "v"), ".")
		out := make([]int, 3)
		for i := 0; i < len(parts) && i < len(out); i++ {
			digits := strings.FieldsFunc(parts[i], func(r rune) bool { return r < '0' || r > '9' })
			if len(digits) > 0 {
				out[i], _ = strconv.Atoi(digits[0])
			}
		}
		return out
	}
	a, b := parse(left), parse(right)
	for i := range a {
		if a[i] < b[i] {
			return -1
		}
		if a[i] > b[i] {
			return 1
		}
	}
	return 0
}
