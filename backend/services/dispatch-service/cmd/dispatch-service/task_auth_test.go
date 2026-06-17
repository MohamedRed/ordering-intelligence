package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestValidateDispatchAuthConfigRequiresTaskOIDC(t *testing.T) {
	cfg := &serviceConfig{
		RequireAuth: true,
	}

	if err := validateDispatchAuthConfig(cfg); err == nil {
		t.Fatal("expected missing task OIDC config to fail validation")
	}
}

func TestValidateDispatchAuthConfigAllowsExplicitAuthOptOut(t *testing.T) {
	cfg := &serviceConfig{
		RequireAuth: false,
	}

	if err := validateDispatchAuthConfig(cfg); err != nil {
		t.Fatalf("expected auth opt-out to skip task OIDC validation: %v", err)
	}
}

func TestRequireDispatchTaskAuthRejectsMissingAudienceOrAllowlist(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/tasks/orders-events", nil)
	rec := httptest.NewRecorder()

	ok := requireDispatchTaskAuth(rec, req, &serviceConfig{RequireAuth: true}, "", nil)

	if ok {
		t.Fatal("expected task auth to reject missing config")
	}
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500 for task auth misconfiguration, got %d", rec.Code)
	}
}

func TestRequireDispatchTaskAuthRejectsMissingBearer(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/tasks/orders-events", nil)
	rec := httptest.NewRecorder()

	ok := requireDispatchTaskAuth(
		rec,
		req,
		&serviceConfig{RequireAuth: true},
		"https://dispatch.example.com",
		[]string{"orders-events@test-project.iam.gserviceaccount.com"},
	)

	if ok {
		t.Fatal("expected task auth to reject missing bearer token")
	}
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for missing bearer token, got %d", rec.Code)
	}
}

func TestRequireDispatchTaskAuthAllowsExplicitAuthOptOut(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/tasks/orders-events", nil)
	rec := httptest.NewRecorder()

	ok := requireDispatchTaskAuth(rec, req, &serviceConfig{RequireAuth: false}, "", nil)

	if !ok {
		t.Fatal("expected task auth to allow explicit auth opt-out")
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("expected handler to stay untouched, got %d", rec.Code)
	}
}
