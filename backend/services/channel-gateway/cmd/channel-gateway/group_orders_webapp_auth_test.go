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

func withStubbedWebAppGroupOrderAuth(
	t *testing.T,
	loadWebAppFn func(ctx context.Context, client *cloudfirestore.Client, sessionID string) (channelSession, error),
	loadWithCustomerFn func(ctx context.Context, cfg *serviceConfig, client *cloudfirestore.Client, sessionID string) (channelSession, error),
	fetchGroupFn func(ctx context.Context, cfg *serviceConfig, client *http.Client, groupID string) (webAppGroupOrderSnapshot, error),
	body func(),
) {
	t.Helper()
	origLoadWebApp := loadWebAppSessionFn
	origLoadWithCustomer := loadWebAppSessionWithCustomerFn
	origFetchGroup := fetchWebAppGroupOrderFn
	if loadWebAppFn != nil {
		loadWebAppSessionFn = loadWebAppFn
	}
	if loadWithCustomerFn != nil {
		loadWebAppSessionWithCustomerFn = loadWithCustomerFn
	}
	if fetchGroupFn != nil {
		fetchWebAppGroupOrderFn = fetchGroupFn
	}
	defer func() {
		loadWebAppSessionFn = origLoadWebApp
		loadWebAppSessionWithCustomerFn = origLoadWithCustomer
		fetchWebAppGroupOrderFn = origFetchGroup
	}()
	body()
}

func TestResolveSessionGroupOrderStoreRejectsStoreOverride(t *testing.T) {
	_, err := resolveSessionGroupOrderStore(channelSession{StoreID: "store-a"}, "store-b")
	if err != errWebAppGroupOrderForbidden {
		t.Fatalf("expected forbidden, got %v", err)
	}
}

func TestAuthorizeWebAppGroupOrderRejectsCrossStore(t *testing.T) {
	withStubbedWebAppGroupOrderAuth(t, nil, nil, func(ctx context.Context, cfg *serviceConfig, client *http.Client, groupID string) (webAppGroupOrderSnapshot, error) {
		return webAppGroupOrderSnapshot{
			ID:      groupID,
			StoreID: "store-b",
		}, nil
	}, func() {
		_, err := authorizeWebAppGroupOrder(
			context.Background(),
			&serviceConfig{OrderServiceURL: "https://orders.example"},
			http.DefaultClient,
			channelSession{StoreID: "store-a", UserID: "user-1"},
			"group-1",
			groupOrderAccessStore,
		)
		if err != errWebAppGroupOrderForbidden {
			t.Fatalf("expected forbidden, got %v", err)
		}
	})
}

func TestAuthorizeWebAppGroupOrderRequiresHostForHostActions(t *testing.T) {
	withStubbedWebAppGroupOrderAuth(t, nil, nil, func(ctx context.Context, cfg *serviceConfig, client *http.Client, groupID string) (webAppGroupOrderSnapshot, error) {
		return webAppGroupOrderSnapshot{
			ID:      groupID,
			StoreID: "store-a",
			Host:    channelContact{UserID: "host-1"},
			Participants: []webAppGroupOrderParticipant{
				{ParticipantID: "user-1"},
			},
		}, nil
	}, func() {
		_, err := authorizeWebAppGroupOrder(
			context.Background(),
			&serviceConfig{OrderServiceURL: "https://orders.example"},
			http.DefaultClient,
			channelSession{StoreID: "store-a", UserID: "user-1"},
			"group-1",
			groupOrderAccessHost,
		)
		if err != errWebAppGroupOrderForbidden {
			t.Fatalf("expected forbidden, got %v", err)
		}
	})
}

func TestHandleWebAppGroupOrderCreateRejectsStoreOverride(t *testing.T) {
	withStubbedWebAppGroupOrderAuth(t, nil, func(ctx context.Context, cfg *serviceConfig, client *cloudfirestore.Client, sessionID string) (channelSession, error) {
		return channelSession{StoreID: "store-a", TenantID: "tenant-1", UserID: "user-1"}, nil
	}, nil, func() {
		req := httptest.NewRequest(
			http.MethodPost,
			"/group-orders",
			strings.NewReader(`{"sessionId":"session-1","storeId":"store-b","paymentMode":"single_payer"}`),
		)
		rec := httptest.NewRecorder()

		handleWebAppGroupOrderCreate(
			rec,
			req,
			&serviceConfig{OrderServiceURL: "https://orders.example"},
			nil,
			http.DefaultClient,
		)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
		}
	})
}

func TestHandleWebAppGroupOrderSubmitRejectsCrossStore(t *testing.T) {
	withStubbedWebAppGroupOrderAuth(t, func(ctx context.Context, client *cloudfirestore.Client, sessionID string) (channelSession, error) {
		return channelSession{StoreID: "store-a", UserID: "host-1"}, nil
	}, nil, func(ctx context.Context, cfg *serviceConfig, client *http.Client, groupID string) (webAppGroupOrderSnapshot, error) {
		return webAppGroupOrderSnapshot{
			ID:      groupID,
			StoreID: "store-b",
			Host:    channelContact{UserID: "host-1"},
		}, nil
	}, func() {
		router := chi.NewRouter()
		router.Post("/group-orders/{groupOrderId}/submit", func(w http.ResponseWriter, r *http.Request) {
			handleWebAppGroupOrderSubmit(
				w,
				r,
				&serviceConfig{OrderServiceURL: "https://orders.example"},
				nil,
				http.DefaultClient,
			)
		})
		req := httptest.NewRequest(http.MethodPost, "/group-orders/group-1/submit", strings.NewReader(`{"sessionId":"session-1"}`))
		rec := httptest.NewRecorder()

		router.ServeHTTP(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
		}
	})
}
