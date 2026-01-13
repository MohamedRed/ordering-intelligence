package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"firebase.google.com/go/v4/auth"
)

func TestDefaultStatus(t *testing.T) {
	if got := defaultStatus(""); got != "active" {
		t.Fatalf("expected active, got %s", got)
	}
	if got := defaultStatus("paused"); got != "paused" {
		t.Fatalf("expected passthrough status")
	}
}

func TestGenerateTenantIDFormat(t *testing.T) {
	id := generateTenantID()
	if id == "" {
		t.Fatalf("id should not be empty")
	}
	if len(id) < len("tenant-1") || id[:7] != "tenant-" {
		t.Fatalf("id should start with tenant-, got %s", id)
	}
}

func TestWriteJSONSetsStatusAndContentType(t *testing.T) {
	rr := httptest.NewRecorder()
	writeJSON(rr, 201, map[string]string{"ok": "true"})
	if rr.Code != 201 {
		t.Fatalf("status expected 201, got %d", rr.Code)
	}
	if ct := rr.Header().Get("Content-Type"); ct != "application/json" {
		t.Fatalf("unexpected content-type %s", ct)
	}
}

func TestStringOrDefault(t *testing.T) {
	if got := stringOrDefault("", "fallback"); got != "fallback" {
		t.Fatalf("expected fallback on empty string")
	}
	if got := stringOrDefault(int64(42), "fallback"); got != "42" {
		t.Fatalf("expected numeric conversion")
	}
	if got := stringOrDefault("value", "fallback"); got != "value" {
		t.Fatalf("expected passthrough value")
	}
}

type fakeAuth struct {
	token *auth.Token
	err   error
}

func (f *fakeAuth) VerifyIDToken(_ context.Context, _ string) (*auth.Token, error) {
	return f.token, f.err
}

func TestFirebaseAuthMiddleware_MissingAuth(t *testing.T) {
	mw := firebaseAuthMiddleware(&fakeAuth{token: &auth.Token{Claims: map[string]interface{}{"role": "admin"}}})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/x", nil)
	mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatalf("handler should not run")
	})).ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestFirebaseAuthMiddleware_ForbidsNonAdmin(t *testing.T) {
	mw := firebaseAuthMiddleware(&fakeAuth{token: &auth.Token{Claims: map[string]interface{}{"role": "user"}}})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/x", nil)
	req.Header.Set("Authorization", "Bearer token")
	mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatalf("handler should not run")
	})).ServeHTTP(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
}

func TestFirebaseAuthMiddleware_AllowsAdmin(t *testing.T) {
	mw := firebaseAuthMiddleware(&fakeAuth{token: &auth.Token{Claims: map[string]interface{}{"role": "admin"}}})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/x", nil)
	req.Header.Set("Authorization", "Bearer token")
	var called bool
	mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusOK)
	})).ServeHTTP(rec, req)
	if !called {
		t.Fatalf("handler should run for admin")
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestLogError(t *testing.T) {
	err := logError("boom")
	if err == nil || err.Error() != "boom" {
		t.Fatalf("logError should return error")
	}
}

func TestNewFirestoreClientMissingProject(t *testing.T) {
	cfg := &serviceConfig{ProjectID: ""}
	if _, err := newFirestoreClient(context.Background(), cfg); err == nil {
		t.Fatalf("expected error when project ID missing")
	}
}

func TestLoadConfigDefaultsPortAndEnv(t *testing.T) {
	t.Setenv("PORT", "")
	cfg, err := loadConfig()
	if err != nil {
		// loadConfig relies on sharedconfig; if it fails due to missing fixture, skip
		t.Skip("sharedconfig not initialized in unit test env")
	}
	if cfg.Port != "8085" {
		t.Fatalf("expected default port 8085, got %s", cfg.Port)
	}
}
