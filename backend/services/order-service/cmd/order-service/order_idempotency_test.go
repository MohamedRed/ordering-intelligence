package main

import (
	"context"
	"errors"
	"testing"

	cloudfirestore "cloud.google.com/go/firestore"
)

func withStubbedFetchOrderByIdempotencyKey(
	t *testing.T,
	fn func(ctx context.Context, client *cloudfirestore.Client, key string) (*orderRecord, error),
	body func(),
) {
	t.Helper()
	orig := fetchOrderByIdempotencyKeyFn
	fetchOrderByIdempotencyKeyFn = fn
	defer func() { fetchOrderByIdempotencyKeyFn = orig }()
	body()
}

func TestFetchIdempotentOrderForStoreRejectsUnauthorizedExistingOrder(t *testing.T) {
	withStubbedFetchOrderByIdempotencyKey(t, func(ctx context.Context, client *cloudfirestore.Client, key string) (*orderRecord, error) {
		if key != "idem-1" {
			t.Fatalf("unexpected key %q", key)
		}
		return &orderRecord{ID: "order-a", StoreID: "store-a"}, nil
	}, func() {
		reqCtx := context.WithValue(context.Background(), authContextKey, authContext{
			StoreIDs: []string{"store-b"},
		})
		existing, err := fetchIdempotentOrderForStore(context.Background(), nil, "idem-1", "store-b", reqCtx, true)
		if !errors.Is(err, errUnauthorizedStore) {
			t.Fatalf("expected unauthorized store error, got %v", err)
		}
		if existing != nil {
			t.Fatalf("expected no existing order on unauthorized replay")
		}
	})
}

func TestFetchIdempotentOrderForStoreRejectsMismatchedRequestedStore(t *testing.T) {
	withStubbedFetchOrderByIdempotencyKey(t, func(ctx context.Context, client *cloudfirestore.Client, key string) (*orderRecord, error) {
		return &orderRecord{ID: "order-a", StoreID: "store-a"}, nil
	}, func() {
		reqCtx := context.WithValue(context.Background(), authContextKey, authContext{})
		existing, err := fetchIdempotentOrderForStore(context.Background(), nil, "idem-1", "store-b", reqCtx, true)
		if !errors.Is(err, errIdempotencyStoreMismatch) {
			t.Fatalf("expected store mismatch error, got %v", err)
		}
		if existing != nil {
			t.Fatalf("expected no existing order on mismatched replay")
		}
	})
}

func TestFetchIdempotentOrderForStoreReturnsMatchingOrder(t *testing.T) {
	withStubbedFetchOrderByIdempotencyKey(t, func(ctx context.Context, client *cloudfirestore.Client, key string) (*orderRecord, error) {
		return &orderRecord{ID: "order-b", StoreID: "store-b"}, nil
	}, func() {
		reqCtx := context.WithValue(context.Background(), authContextKey, authContext{
			StoreIDs: []string{"store-b"},
		})
		existing, err := fetchIdempotentOrderForStore(context.Background(), nil, "idem-1", "store-b", reqCtx, true)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if existing == nil || existing.ID != "order-b" {
			t.Fatalf("expected matching order, got %#v", existing)
		}
	})
}
