package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
)

func TestHandleMenuGetRequiresStoreAccess(t *testing.T) {
	router := chi.NewRouter()
	cfg := &serviceConfig{RequireAuth: true}
	router.Get("/stores/{storeID}/menu", func(w http.ResponseWriter, r *http.Request) {
		handleMenuGet(context.Background(), nil, cfg, w, r)
	})

	req := httptest.NewRequest(http.MethodGet, "/stores/store-a/menu", nil)
	req = req.WithContext(context.WithValue(req.Context(), authContextKey, authContext{
		UID:      "business-user",
		Role:     "manager",
		StoreIDs: []string{"store-b"},
	}))
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for out-of-scope store read, got %d body=%s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "forbidden") {
		t.Fatalf("expected forbidden error body, got %s", rec.Body.String())
	}
}

func TestHandleMenuUpsertRequiresStoreAccess(t *testing.T) {
	router := chi.NewRouter()
	cfg := &serviceConfig{RequireAuth: true}
	router.Put("/stores/{storeID}/menu", func(w http.ResponseWriter, r *http.Request) {
		handleMenuUpsert(context.Background(), nil, cfg, w, r)
	})

	req := httptest.NewRequest(http.MethodPut, "/stores/store-a/menu", strings.NewReader(`{}`))
	req = req.WithContext(context.WithValue(req.Context(), authContextKey, authContext{
		UID:      "business-user",
		Role:     "manager",
		StoreIDs: []string{"store-b"},
	}))
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for out-of-scope store write, got %d body=%s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "forbidden") {
		t.Fatalf("expected forbidden error body, got %s", rec.Body.String())
	}
}

func TestHandleMenuUpsertChecksPayloadAfterStoreAccess(t *testing.T) {
	router := chi.NewRouter()
	cfg := &serviceConfig{RequireAuth: true}
	router.Put("/stores/{storeID}/menu", func(w http.ResponseWriter, r *http.Request) {
		handleMenuUpsert(context.Background(), nil, cfg, w, r)
	})

	req := httptest.NewRequest(http.MethodPut, "/stores/store-a/menu", strings.NewReader(`not-json`))
	req = req.WithContext(context.WithValue(req.Context(), authContextKey, authContext{
		UID:      "business-user",
		Role:     "manager",
		StoreIDs: []string{"store-a"},
	}))
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid payload after passing store scope, got %d body=%s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "invalid_payload") {
		t.Fatalf("expected invalid_payload error body, got %s", rec.Body.String())
	}
}
