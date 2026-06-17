package main

import (
	"context"
	"net/http"

	cloudfirestore "cloud.google.com/go/firestore"
)

func requireGroupOrderStoreAccess(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	storeID string,
) bool {
	if cfg == nil || !cfg.RequireAuth || canAccessStore(r.Context(), storeID) {
		return true
	}
	writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
	return false
}

func requireGroupOrderSessionAccess(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	session groupOrderSession,
) bool {
	return requireGroupOrderStoreAccess(w, r, cfg, session.StoreID)
}

func updateGroupOrderWithStoreAccess(
	ctx context.Context,
	client *cloudfirestore.Client,
	id string,
	reqCtx context.Context,
	cfg *serviceConfig,
	mutate func(groupOrderSession) (groupOrderSession, error),
) (groupOrderSession, error) {
	return updateGroupOrderFn(ctx, client, id, func(current groupOrderSession) (groupOrderSession, error) {
		if cfg != nil && cfg.RequireAuth && !canAccessStore(reqCtx, current.StoreID) {
			return current, errUnauthorizedStore
		}
		return mutate(current)
	})
}
