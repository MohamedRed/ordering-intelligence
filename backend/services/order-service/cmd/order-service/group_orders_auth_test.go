package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

func withStubbedGroupOrderStore(
	t *testing.T,
	createFn func(ctx context.Context, client *cloudfirestore.Client, session groupOrderSession) error,
	fetchFn func(ctx context.Context, client *cloudfirestore.Client, id string) (groupOrderSession, error),
	updateFn func(ctx context.Context, client *cloudfirestore.Client, id string, mutate func(groupOrderSession) (groupOrderSession, error)) (groupOrderSession, error),
	body func(),
) {
	t.Helper()
	origCreate := createGroupOrderFn
	origFetch := fetchGroupOrderFn
	origUpdate := updateGroupOrderFn
	if createFn != nil {
		createGroupOrderFn = createFn
	}
	if fetchFn != nil {
		fetchGroupOrderFn = fetchFn
	}
	if updateFn != nil {
		updateGroupOrderFn = updateFn
	}
	defer func() {
		createGroupOrderFn = origCreate
		fetchGroupOrderFn = origFetch
		updateGroupOrderFn = origUpdate
	}()
	body()
}

func TestGroupOrderCreateRejectsOutOfScopeStore(t *testing.T) {
	createCalled := false
	withStubbedGroupOrderStore(t, func(ctx context.Context, client *cloudfirestore.Client, session groupOrderSession) error {
		createCalled = true
		return nil
	}, nil, nil, func() {
		req := httptest.NewRequest(
			http.MethodPost,
			"/group_orders",
			strings.NewReader(`{"tenantId":"tenant-1","storeId":"store-a","host":{"userId":"host-1"}}`),
		)
		req = req.WithContext(context.WithValue(req.Context(), authContextKey, authContext{
			StoreIDs: []string{"store-b"},
		}))
		rec := httptest.NewRecorder()

		handleGroupOrderCreate(rec, req, nil, &serviceConfig{RequireAuth: true})

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
		}
		if createCalled {
			t.Fatalf("create should not run for out-of-scope store")
		}
	})
}

func TestGroupOrderSubmitRejectsOutOfScopeStore(t *testing.T) {
	withStubbedGroupOrderStore(t, nil, func(ctx context.Context, client *cloudfirestore.Client, id string) (groupOrderSession, error) {
		if id != "group-1" {
			t.Fatalf("unexpected group id %q", id)
		}
		return groupOrderSession{
			ID:      "group-1",
			StoreID: "store-a",
			Status:  groupOrderStatusLocked,
		}, nil
	}, nil, func() {
		router := chi.NewRouter()
		router.Post("/group_orders/{groupOrderId}/submit", func(w http.ResponseWriter, r *http.Request) {
			handleGroupOrderSubmit(w, r, nil, nil, &serviceConfig{RequireAuth: true})
		})
		req := httptest.NewRequest(http.MethodPost, "/group_orders/group-1/submit", strings.NewReader(`{}`))
		req = req.WithContext(context.WithValue(req.Context(), authContextKey, authContext{
			StoreIDs: []string{"store-b"},
		}))
		rec := httptest.NewRecorder()

		router.ServeHTTP(rec, req)

		if rec.Code != http.StatusForbidden {
			t.Fatalf("expected 403, got %d body=%s", rec.Code, rec.Body.String())
		}
	})
}

func TestUpdateGroupOrderWithStoreAccessRejectsOutOfScopeStore(t *testing.T) {
	withStubbedGroupOrderStore(t, nil, nil, func(ctx context.Context, client *cloudfirestore.Client, id string, mutate func(groupOrderSession) (groupOrderSession, error)) (groupOrderSession, error) {
		return mutate(groupOrderSession{ID: id, StoreID: "store-a"})
	}, func() {
		reqCtx := context.WithValue(context.Background(), authContextKey, authContext{
			StoreIDs: []string{"store-b"},
		})

		_, err := updateGroupOrderWithStoreAccess(
			context.Background(),
			nil,
			"group-1",
			reqCtx,
			&serviceConfig{RequireAuth: true},
			func(current groupOrderSession) (groupOrderSession, error) {
				t.Fatalf("mutation should not run for out-of-scope store")
				return current, nil
			},
		)

		if !errors.Is(err, errUnauthorizedStore) {
			t.Fatalf("expected unauthorized store error, got %v", err)
		}
	})
}
