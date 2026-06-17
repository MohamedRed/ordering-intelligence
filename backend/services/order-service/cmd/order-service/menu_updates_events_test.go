package main

import (
	"context"
	"encoding/base64"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

func menuUpdatePushBody(payload string) string {
	encoded := base64.StdEncoding.EncodeToString([]byte(payload))
	return `{"message":{"data":"` + encoded + `"}}`
}

func TestMenuUpdatesHandlerInvalidatesCache(t *testing.T) {
	menuCache = sync.Map{}
	menuCache.Store("store-invalidate", cachedMenu{menu: &menuRecord{StoreID: "store-invalidate"}, expires: time.Now().Add(5 * time.Minute)})

	withStubbedFetchMenu(t, func(ctx context.Context, client *firestore.Client, storeID string) (*menuRecord, error) {
		return &menuRecord{StoreID: storeID}, nil
	}, func() {
		handler := menuUpdatesHandler(context.Background(), nil)
		req := httptest.NewRequest(
			http.MethodPost,
			"/events/menu-updates",
			strings.NewReader(menuUpdatePushBody(`{"storeId":"store-invalidate","updatedAt":"2024-01-01T00:00:00Z","jobId":"j1","source":"test"}`)),
		)
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

func TestMenuUpdatesHandlerAcknowledgesMalformedPayloads(t *testing.T) {
	tests := []struct {
		name   string
		body   string
		reason string
	}{
		{name: "invalid envelope", body: `{`, reason: menuUpdateDecodeInvalidPayload},
		{name: "missing data", body: `{}`, reason: menuUpdateDecodeMissingData},
		{name: "bad base64", body: `{"message":{"data":"###"}}`, reason: menuUpdateDecodeBadBase64},
		{name: "invalid event", body: menuUpdatePushBody(`{"invalid":true}`), reason: menuUpdateDecodeInvalidEvent},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			handler := menuUpdatesHandler(context.Background(), nil)
			req := httptest.NewRequest(http.MethodPost, "/events/menu-updates", strings.NewReader(tc.body))
			rr := httptest.NewRecorder()

			handler(rr, req)

			if rr.Code != http.StatusOK {
				t.Fatalf("expected 200, got %d body=%s", rr.Code, rr.Body.String())
			}
			if !strings.Contains(rr.Body.String(), tc.reason) {
				t.Fatalf("expected reason %q in response body, got %s", tc.reason, rr.Body.String())
			}
		})
	}
}
