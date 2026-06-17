package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	cloudfirestore "cloud.google.com/go/firestore"
)

func TestHandleOrderCreateRejectsIdempotentOrderOutsideCallerStore(t *testing.T) {
	withStubbedFetchOrderByIdempotencyKey(t, func(ctx context.Context, client *cloudfirestore.Client, key string) (*orderRecord, error) {
		return &orderRecord{ID: "order-a", StoreID: "store-a"}, nil
	}, func() {
		req := httptest.NewRequest(
			http.MethodPost,
			"/orders",
			strings.NewReader(`{"storeId":"store-b","idempotencyKey":"idem-1","items":[{"itemId":"burger","quantity":1,"priceCents":900}]}`),
		)
		req = req.WithContext(context.WithValue(req.Context(), authContextKey, authContext{
			StoreIDs: []string{"store-b"},
		}))
		rec := httptest.NewRecorder()

		handleOrderCreate(context.Background(), nil, nil, &serviceConfig{RequireAuth: true, OrderTTLDays: 30}, rec, req)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
		}
	})
}

func TestHandleOrderCreateRejectsMismatchedIdempotentStoreForAdmin(t *testing.T) {
	withStubbedFetchOrderByIdempotencyKey(t, func(ctx context.Context, client *cloudfirestore.Client, key string) (*orderRecord, error) {
		return &orderRecord{ID: "order-a", StoreID: "store-a"}, nil
	}, func() {
		req := httptest.NewRequest(
			http.MethodPost,
			"/orders",
			strings.NewReader(`{"storeId":"store-b","idempotencyKey":"idem-1","items":[{"itemId":"burger","quantity":1,"priceCents":900}]}`),
		)
		req = req.WithContext(context.WithValue(req.Context(), authContextKey, authContext{}))
		rec := httptest.NewRecorder()

		handleOrderCreate(context.Background(), nil, nil, &serviceConfig{RequireAuth: true, OrderTTLDays: 30}, rec, req)

		if rec.Code != http.StatusConflict {
			t.Fatalf("expected 409, got %d body=%s", rec.Code, rec.Body.String())
		}
		if !strings.Contains(rec.Body.String(), "idempotency_store_mismatch") {
			t.Fatalf("expected mismatch error body, got %s", rec.Body.String())
		}
	})
}
