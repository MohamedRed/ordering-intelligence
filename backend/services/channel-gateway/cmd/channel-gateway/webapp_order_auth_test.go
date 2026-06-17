package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	cloudfirestore "cloud.google.com/go/firestore"
)

func withStubbedWebAppOrderAuth(
	t *testing.T,
	loadWithCustomerFn func(ctx context.Context, cfg *serviceConfig, client *cloudfirestore.Client, sessionID string) (channelSession, error),
	fetchOrderFn func(ctx context.Context, cfg *serviceConfig, client *http.Client, orderID string) (webAppOrderSnapshot, error),
	body func(),
) {
	t.Helper()
	origLoadWithCustomer := loadSessionWithCustomerFn
	origFetchOrder := fetchWebAppOrderFn
	if loadWithCustomerFn != nil {
		loadSessionWithCustomerFn = loadWithCustomerFn
	}
	if fetchOrderFn != nil {
		fetchWebAppOrderFn = fetchOrderFn
	}
	defer func() {
		loadSessionWithCustomerFn = origLoadWithCustomer
		fetchWebAppOrderFn = origFetchOrder
	}()
	body()
}

func TestResolveSessionOrderStoreRejectsStoreOverride(t *testing.T) {
	_, err := resolveSessionOrderStore(channelSession{StoreID: "store-a"}, "store-b")
	if err != errWebAppOrderForbidden {
		t.Fatalf("expected forbidden, got %v", err)
	}
}

func TestAuthorizeSessionOrderRejectsCustomerMismatch(t *testing.T) {
	withStubbedWebAppOrderAuth(t, nil, func(ctx context.Context, cfg *serviceConfig, client *http.Client, orderID string) (webAppOrderSnapshot, error) {
		return webAppOrderSnapshot{
			ID:         orderID,
			StoreID:    "store-a",
			CustomerID: "customer-b",
		}, nil
	}, func() {
		_, err := authorizeSessionOrder(
			context.Background(),
			&serviceConfig{OrderServiceURL: "https://orders.example"},
			http.DefaultClient,
			channelSession{StoreID: "store-a", CustomerID: "customer-a"},
			"order-1",
		)
		if err != errWebAppOrderForbidden {
			t.Fatalf("expected forbidden, got %v", err)
		}
	})
}

func TestHandleWebAppOrderCreateRejectsStoreOverride(t *testing.T) {
	withStubbedWebAppOrderAuth(t, func(ctx context.Context, cfg *serviceConfig, client *cloudfirestore.Client, sessionID string) (channelSession, error) {
		return channelSession{
			Channel:    "telegram_webapp",
			StoreID:    "store-a",
			TenantID:   "tenant-1",
			CustomerID: "customer-1",
			UserID:     "user-1",
		}, nil
	}, nil, func() {
		req := httptest.NewRequest(
			http.MethodPost,
			"/orders",
			strings.NewReader(`{"sessionId":"session-1","storeId":"store-b","items":[{"itemId":"burger","quantity":1}]}`),
		)
		rec := httptest.NewRecorder()

		handleWebAppOrderCreate(
			rec,
			req,
			&serviceConfig{OrderServiceURL: "https://orders.example"},
			nil,
			http.DefaultClient,
			http.DefaultClient,
		)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
		}
	})
}

func TestHandleMobileOrderPaymentIntentRejectsCustomerMismatch(t *testing.T) {
	withStubbedWebAppOrderAuth(t, func(ctx context.Context, cfg *serviceConfig, client *cloudfirestore.Client, sessionID string) (channelSession, error) {
		return channelSession{
			Channel:    "mobile",
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
		req := httptest.NewRequest(http.MethodPost, "/mobile/orders/order-1/payment-intent", strings.NewReader(`{"sessionId":"session-1"}`))
		rec := httptest.NewRecorder()

		handleMobileOrderPaymentIntent(
			rec,
			req,
			&serviceConfig{
				OrderServiceURL:    "https://orders.example",
				PaymentsServiceURL: "https://payments.example",
			},
			nil,
			http.DefaultClient,
			http.DefaultClient,
			"order-1",
		)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
		}
	})
}

func TestHandleMobileOrderPayDefaultRejectsCustomerMismatch(t *testing.T) {
	withStubbedWebAppOrderAuth(t, func(ctx context.Context, cfg *serviceConfig, client *cloudfirestore.Client, sessionID string) (channelSession, error) {
		return channelSession{
			Channel:    "mobile",
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
		req := httptest.NewRequest(http.MethodPost, "/mobile/orders/order-1/pay-default", strings.NewReader(`{"sessionId":"session-1"}`))
		rec := httptest.NewRecorder()

		handleMobileOrderPayDefault(
			rec,
			req,
			&serviceConfig{
				OrderServiceURL:    "https://orders.example",
				PaymentsServiceURL: "https://payments.example",
			},
			nil,
			http.DefaultClient,
			http.DefaultClient,
			"order-1",
		)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
		}
	})
}
