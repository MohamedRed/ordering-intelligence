package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestParseCORSOriginsRequiresExplicitOrigins(t *testing.T) {
	if _, err := parseCORSOrigins(""); err == nil {
		t.Fatalf("expected empty CORS_ORIGINS to fail")
	}
	if _, err := parseCORSOrigins(" , "); err == nil {
		t.Fatalf("expected blank CORS_ORIGINS entries to fail")
	}
}

func TestParseCORSOriginsRejectsWildcard(t *testing.T) {
	if _, err := parseCORSOrigins("https://admin.example.com,*"); err == nil {
		t.Fatalf("expected wildcard CORS origin to fail")
	}
}

func TestParseCORSOriginsRejectsInvalidOrigin(t *testing.T) {
	invalid := []string{
		"admin.example.com",
		"https://admin.example.com/path",
		"https://admin.example.com?debug=true",
		"ftp://admin.example.com",
	}
	for _, raw := range invalid {
		t.Run(raw, func(t *testing.T) {
			if _, err := parseCORSOrigins(raw); err == nil {
				t.Fatalf("expected %q to fail", raw)
			}
		})
	}
}

func TestParseCORSOriginsTrimsAndDeduplicates(t *testing.T) {
	origins, err := parseCORSOrigins(" https://admin.example.com, http://localhost:3000,https://admin.example.com ")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{"https://admin.example.com", "http://localhost:3000"}
	if len(origins) != len(want) {
		t.Fatalf("expected %d origins, got %d: %#v", len(want), len(origins), origins)
	}
	for i := range want {
		if origins[i] != want[i] {
			t.Fatalf("origin[%d] expected %q, got %q", i, want[i], origins[i])
		}
	}
}

func TestCORSMiddlewareAllowsConfiguredOrigin(t *testing.T) {
	mw := corsMiddleware([]string{"https://admin.example.com"})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodOptions, "/tenants", nil)
	req.Header.Set("Origin", "https://admin.example.com")
	req.Header.Set("Access-Control-Request-Method", http.MethodGet)

	mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatalf("preflight should not reach handler")
	})).ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "https://admin.example.com" {
		t.Fatalf("unexpected allow origin %q", got)
	}
}

func TestCORSMiddlewareDoesNotAllowUnknownOrigin(t *testing.T) {
	mw := corsMiddleware([]string{"https://admin.example.com"})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/tenants", nil)
	req.Header.Set("Origin", "https://business.example.com")

	mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("expected unknown origin to be blocked, got %q", got)
	}
}
