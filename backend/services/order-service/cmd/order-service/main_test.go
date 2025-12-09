package main

import (
	"encoding/base64"
	cloudfirestore "cloud.google.com/go/firestore"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"context"
	"firebase.google.com/go/v4/auth"
)

// Helper to stub fetchMenuFn during tests.
func withStubbedFetchMenu(t *testing.T, fn func(ctx context.Context, client *firestore.Client, storeID string) (*menuRecord, error), body func()) {
	t.Helper()
	orig := fetchMenuFn
	fetchMenuFn = fn
	defer func() { fetchMenuFn = orig }()
	body()
}

type fakeAuth struct {
	token *auth.Token
	err   error
}

func (f *fakeAuth) VerifyIDToken(_ context.Context, _ string) (*auth.Token, error) {
	if f.err != nil {
		return nil, f.err
	}
	return f.token, nil
}

func TestFetchMenuCachedHitMissAndTTL(t *testing.T) {
	menuCache = sync.Map{}
	atomic.StoreUint64(&menuCacheHits, 0)
	atomic.StoreUint64(&menuCacheMisses, 0)

	withStubbedFetchMenu(t, func(ctx context.Context, client *firestore.Client, storeID string) (*menuRecord, error) {
		return &menuRecord{StoreID: storeID, UpdatedAt: time.Now()}, nil
	}, func() {
		ctx := context.Background()
		storeID := "s1"
		// miss and populate
		if _, err := fetchMenuCached(ctx, nil, storeID); err != nil {
			t.Fatalf("fetchMenuCached miss err: %v", err)
		}
		if atomic.LoadUint64(&menuCacheMisses) != 1 {
			t.Fatalf("expected 1 miss")
		}
		// hit
		if _, err := fetchMenuCached(ctx, nil, storeID); err != nil {
			t.Fatalf("fetchMenuCached hit err: %v", err)
		}
		if atomic.LoadUint64(&menuCacheHits) != 1 {
			t.Fatalf("expected 1 hit")
		}
	})

	// TTL expiry should cause a miss
	menuCache = sync.Map{}
	menuCache.Store("s2", cachedMenu{menu: &menuRecord{StoreID: "s2"}, expires: time.Now().Add(-1 * time.Minute)})
	atomic.StoreUint64(&menuCacheMisses, 0)
	withStubbedFetchMenu(t, func(ctx context.Context, client *firestore.Client, storeID string) (*menuRecord, error) {
		return &menuRecord{StoreID: storeID}, nil
	}, func() {
		if _, err := fetchMenuCached(context.Background(), nil, "s2"); err != nil {
			t.Fatalf("fetchMenuCached after expiry err: %v", err)
		}
		if atomic.LoadUint64(&menuCacheMisses) != 1 {
			t.Fatalf("expected miss after expiry")
		}
	})
}

func TestMenuUpdatesHandlerInvalidatesCache(t *testing.T) {
	menuCache = sync.Map{}
	menuCache.Store("store-invalidate", cachedMenu{menu: &menuRecord{StoreID: "store-invalidate"}, expires: time.Now().Add(5 * time.Minute)})

	withStubbedFetchMenu(t, func(ctx context.Context, client *firestore.Client, storeID string) (*menuRecord, error) {
		return &menuRecord{StoreID: storeID}, nil
	}, func() {
		handler := menuUpdatesHandler(context.Background(), nil)
		payload := base64.StdEncoding.EncodeToString([]byte(`{"storeId":"store-invalidate","updatedAt":"2024-01-01T00:00:00Z","jobId":"j1","source":"test"}`))
		req := httptest.NewRequest(http.MethodPost, "/events/menu-updates", strings.NewReader(`{"message":{"data":"`+payload+`"}}`))
		rr := httptest.NewRecorder()

		handler(rr, req)

		if rr.Code != http.StatusNoContent {
			t.Fatalf("expected 204, got %d", rr.Code)
		}
		if v, ok := menuCache.Load("store-invalidate"); !ok {
			t.Fatalf("cache entry should be refreshed")
		} else {
			cm := v.(cachedMenu)
			if cm.menu.StoreID != "store-invalidate" {
				t.Fatalf("unexpected store in cache")
			}
			if time.Until(cm.expires) <= 0 {
				t.Fatalf("cache expiry not extended")
			}
		}
	})
}

func TestMenuUpdatesHandlerRejectsBadPayload(t *testing.T) {
	handler := menuUpdatesHandler(context.Background(), nil)
	req := httptest.NewRequest(http.MethodPost, "/events/menu-updates", strings.NewReader(`{}`))
	rr := httptest.NewRecorder()
	handler(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for missing data, got %d", rr.Code)
	}
}

func TestMenuUpdatesHandlerBadBase64(t *testing.T) {
	handler := menuUpdatesHandler(context.Background(), nil)
	req := httptest.NewRequest(http.MethodPost, "/events/menu-updates", strings.NewReader(`{"message":{"data":"###"}}`))
	rr := httptest.NewRecorder()
	handler(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for bad base64, got %d", rr.Code)
	}
}

func TestMenuUpdatesHandlerInvalidEvent(t *testing.T) {
	handler := menuUpdatesHandler(context.Background(), nil)
	payload := base64.StdEncoding.EncodeToString([]byte(`{"invalid":true}`))
	req := httptest.NewRequest(http.MethodPost, "/events/menu-updates", strings.NewReader(`{"message":{"data":"`+payload+`"}}`))
	rr := httptest.NewRecorder()
	handler(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid event, got %d", rr.Code)
	}
}

func TestMetricsHandlerOutputsCounters(t *testing.T) {
	atomic.StoreUint64(&ordersCreatedCounter, 2)
	atomic.StoreUint64(&statusUpdateCounter, 3)
	atomic.StoreUint64(&menuCacheHits, 4)
	atomic.StoreUint64(&menuCacheMisses, 5)

	rr := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	metricsHandler(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rr.Code)
	}
	body := rr.Body.String()
	for _, s := range []string{
		"orders_created_total 2",
		"order_status_updates_total 3",
		"menu_cache_hits_total 4",
		"menu_cache_misses_total 5",
	} {
		if !strings.Contains(body, s) {
			t.Fatalf("missing metric %q in body: %s", s, body)
		}
	}
}

func TestWriteJSONSetsContentType(t *testing.T) {
	rr := httptest.NewRecorder()
	writeJSON(rr, http.StatusTeapot, map[string]string{"ok": "yes"})
	if rr.Code != http.StatusTeapot {
		t.Fatalf("expected 418, got %d", rr.Code)
	}
	if ct := rr.Header().Get("Content-Type"); ct != "application/json" {
		t.Fatalf("expected application/json, got %s", ct)
	}
}

func TestFetchMenuCachedNilMenu(t *testing.T) {
	menuCache = sync.Map{}
	atomic.StoreUint64(&menuCacheHits, 0)
	atomic.StoreUint64(&menuCacheMisses, 0)
	orig := fetchMenuFn
	fetchMenuFn = func(ctx context.Context, client *cloudfirestore.Client, storeID string) (*menuRecord, error) {
		return nil, nil
	}
	defer func() { fetchMenuFn = orig }()

	menu, err := fetchMenuCached(context.Background(), nil, "store-x")
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	if menu != nil {
		t.Fatalf("expected nil menu")
	}
	if atomic.LoadUint64(&menuCacheMisses) != 1 {
		t.Fatalf("expected miss counter increment")
	}
}

func TestCanAccessStore(t *testing.T) {
	ctx := context.WithValue(context.Background(), authContextKey, authContext{
		StoreIDs: []string{"s1", "s2"},
	})
	if !canAccessStore(ctx, "s1") {
		t.Fatalf("expected access to s1")
	}
	if canAccessStore(ctx, "s3") {
		t.Fatalf("should not allow s3")
	}
	// empty store list means admin/full access
	ctx2 := context.WithValue(context.Background(), authContextKey, authContext{
		StoreIDs: []string{},
	})
	if !canAccessStore(ctx2, "any") {
		t.Fatalf("expected access when list empty")
	}
	if canAccessStore(context.Background(), "s1") {
		t.Fatalf("should deny when no context")
	}
	if canAccessStore(ctx, "") {
		t.Fatalf("should deny empty store id")
	}
	// wrong type in context should deny
	ctx3 := context.WithValue(context.Background(), authContextKey, "not-auth-context")
	if canAccessStore(ctx3, "s1") {
		t.Fatalf("should deny when context value wrong type")
	}
}

func TestFirebaseAuthMiddlewareMissingHeader(t *testing.T) {
	mw := firebaseAuthMiddleware(&fakeAuth{token: &auth.Token{UID: "u", Claims: map[string]interface{}{"role": "admin"}}})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/x", nil)
	mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatalf("handler should not run")
	})).ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestFirebaseAuthMiddlewareInvalidPrefix(t *testing.T) {
	mw := firebaseAuthMiddleware(&fakeAuth{token: &auth.Token{UID: "u", Claims: map[string]interface{}{"role": "admin"}}})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/x", nil)
	req.Header.Set("Authorization", "Token abc")
	mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatalf("handler should not run")
	})).ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestFirebaseAuthMiddlewareForbiddenRole(t *testing.T) {
	mw := firebaseAuthMiddleware(&fakeAuth{token: &auth.Token{UID: "u", Claims: map[string]interface{}{"role": "user"}}})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/x", nil)
	req.Header.Set("Authorization", "Bearer token")
	var storeIDs []string
	mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if ac, ok := r.Context().Value(authContextKey).(authContext); ok {
			storeIDs = ac.StoreIDs
		}
		w.WriteHeader(http.StatusOK)
	})).ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if len(storeIDs) != 0 {
		t.Fatalf("expected no store IDs when none provided")
	}
}

func TestFirebaseAuthMiddlewareAllowsAdmin(t *testing.T) {
	mw := firebaseAuthMiddleware(&fakeAuth{token: &auth.Token{UID: "u", Claims: map[string]interface{}{"role": "admin", "storeIds": []interface{}{"s1"}}}})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/x", nil)
	req.Header.Set("Authorization", "Bearer token")
	mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})).ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}
