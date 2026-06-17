package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

func TestHandleWebAppFuelPumpUpdateRequiresSession(t *testing.T) {
	req := httptest.NewRequest(
		http.MethodPost,
		"/telegram/webapp/orders/order-1/fuel/pump",
		strings.NewReader(`{"pumpNumber":"3"}`),
	)
	rec := httptest.NewRecorder()

	handleWebAppFuelPumpUpdate(
		rec,
		req,
		&serviceConfig{OrderServiceURL: "https://orders.example"},
		nil,
		http.DefaultClient,
		"order-1",
	)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d body=%s", rec.Code, rec.Body.String())
	}
}

func TestHandleWebAppFuelPumpUpdateRejectsCustomerMismatch(t *testing.T) {
	withStubbedWebAppOrderAuth(t, func(ctx context.Context, cfg *serviceConfig, client *cloudfirestore.Client, sessionID string) (channelSession, error) {
		return channelSession{
			Channel:    "telegram_webapp",
			StoreID:    "store-a",
			CustomerID: "customer-a",
			UserID:     "user-1",
		}, nil
	}, func(ctx context.Context, cfg *serviceConfig, client *http.Client, orderID string) (webAppOrderSnapshot, error) {
		return webAppOrderSnapshot{
			ID:         orderID,
			StoreID:    "store-a",
			CustomerID: "customer-b",
		}, nil
	}, func() {
		req := httptest.NewRequest(
			http.MethodPost,
			"/telegram/webapp/orders/order-1/fuel/pump",
			strings.NewReader(`{"sessionId":"session-1","pumpNumber":"3"}`),
		)
		rec := httptest.NewRecorder()
		orderClient := &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
			t.Fatalf("order fuel update should not be called after an auth failure")
			return nil, nil
		})}

		handleWebAppFuelPumpUpdate(
			rec,
			req,
			&serviceConfig{OrderServiceURL: "https://orders.example"},
			nil,
			orderClient,
			"order-1",
		)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
		}
	})
}

func TestHandleWebAppOrderUpdatesLinkRejectsCustomerMismatch(t *testing.T) {
	withStubbedWebAppOrderAuth(t, func(ctx context.Context, cfg *serviceConfig, client *cloudfirestore.Client, sessionID string) (channelSession, error) {
		return channelSession{
			Channel:     "telegram_webapp",
			AccountID:   "telegram_webapp",
			StoreID:     "store-a",
			CustomerID:  "customer-a",
			UserID:      "12345",
			DisplayName: "CI User",
		}, nil
	}, func(ctx context.Context, cfg *serviceConfig, client *http.Client, orderID string) (webAppOrderSnapshot, error) {
		return webAppOrderSnapshot{
			ID:         orderID,
			StoreID:    "store-a",
			CustomerID: "customer-b",
		}, nil
	}, func() {
		router := chi.NewRouter()
		orderClient := &http.Client{Transport: roundTripFunc(func(req *http.Request) (*http.Response, error) {
			t.Fatalf("order contact update should not be called after an auth failure")
			return nil, nil
		})}
		router.Post("/orders/{orderId}/link-updates", func(w http.ResponseWriter, r *http.Request) {
			handleWebAppOrderUpdatesLink(
				w,
				r,
				&serviceConfig{OrderServiceURL: "https://orders.example"},
				nil,
				orderClient,
			)
		})
		req := httptest.NewRequest(http.MethodPost, "/orders/order-1/link-updates", strings.NewReader(`{"sessionId":"session-1"}`))
		rec := httptest.NewRecorder()

		router.ServeHTTP(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
		}
	})
}
