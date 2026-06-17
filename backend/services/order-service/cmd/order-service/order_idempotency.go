package main

import (
	"context"
	"errors"
	"net/http"
	"strings"

	cloudfirestore "cloud.google.com/go/firestore"
)

var fetchOrderByIdempotencyKeyFn = fetchOrderByIdempotencyKey

var errIdempotencyStoreMismatch = errors.New("idempotency_store_mismatch")

func fetchIdempotentOrderForStore(
	ctx context.Context,
	client *cloudfirestore.Client,
	key string,
	storeID string,
	reqCtx context.Context,
	requireAuth bool,
) (*orderRecord, error) {
	existing, err := fetchOrderByIdempotencyKeyFn(ctx, client, strings.TrimSpace(key))
	if err != nil || existing == nil {
		return existing, err
	}
	if requireAuth && !canAccessStore(reqCtx, existing.StoreID) {
		return nil, errUnauthorizedStore
	}
	if strings.TrimSpace(existing.StoreID) != strings.TrimSpace(storeID) {
		return nil, errIdempotencyStoreMismatch
	}
	return existing, nil
}

func writeIdempotencyError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, errUnauthorizedStore):
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
	case errors.Is(err, errIdempotencyStoreMismatch):
		writeJSON(w, http.StatusConflict, map[string]string{"error": "idempotency_store_mismatch"})
	default:
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "idempotency_lookup_failed"})
	}
}
