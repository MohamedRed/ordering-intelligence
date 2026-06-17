package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	cloudfirestore "cloud.google.com/go/firestore"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (fn roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return fn(req)
}

func TestHandleWebAppDeliveryPrewarmRejectsStoreOverride(t *testing.T) {
	withStubbedWebAppOrderAuth(t, func(ctx context.Context, cfg *serviceConfig, client *cloudfirestore.Client, sessionID string) (channelSession, error) {
		return channelSession{
			Channel:    "telegram_webapp",
			StoreID:    "store-a",
			CustomerID: "customer-1",
			UserID:     "user-1",
		}, nil
	}, nil, func() {
		req := httptest.NewRequest(
			http.MethodPost,
			"/webapp/delivery/prewarm",
			strings.NewReader(`{"sessionId":"session-1","storeId":"store-b","dropoffAddressText":"1 Main St"}`),
		)
		rec := httptest.NewRecorder()
		dispatchClient := &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
			t.Fatalf("dispatch should not be called for a store override")
			return nil, nil
		})}

		handleWebAppDeliveryPrewarm(
			rec,
			req,
			&serviceConfig{DispatchServiceURL: "https://dispatch.example"},
			nil,
			dispatchClient,
		)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
		}
	})
}

func TestHandleWebAppDeliveryPrewarmUsesSessionStore(t *testing.T) {
	withStubbedWebAppOrderAuth(t, func(ctx context.Context, cfg *serviceConfig, client *cloudfirestore.Client, sessionID string) (channelSession, error) {
		return channelSession{
			Channel:    "telegram_webapp",
			StoreID:    "store a",
			CustomerID: "customer-1",
			UserID:     "user-1",
		}, nil
	}, nil, func() {
		dispatchServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.EscapedPath() != "/v1/stores/store%20a/marketplace/prewarm" {
				t.Fatalf("unexpected dispatch path: %s", r.URL.EscapedPath())
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"status":"ready"}`))
		}))
		defer dispatchServer.Close()

		req := httptest.NewRequest(
			http.MethodPost,
			"/webapp/delivery/prewarm",
			strings.NewReader(`{"sessionId":"session-1","dropoffAddressText":"1 Main St"}`),
		)
		rec := httptest.NewRecorder()

		handleWebAppDeliveryPrewarm(
			rec,
			req,
			&serviceConfig{DispatchServiceURL: dispatchServer.URL},
			nil,
			dispatchServer.Client(),
		)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d body=%s", rec.Code, rec.Body.String())
		}
	})
}
