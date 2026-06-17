package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

func handleMenuGet(
	ctx context.Context,
	firestoreClient *cloudfirestore.Client,
	cfg *serviceConfig,
	w http.ResponseWriter,
	r *http.Request,
) {
	storeID := chi.URLParam(r, "storeID")
	if storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
		return
	}
	if cfg.RequireAuth && !canAccessStore(r.Context(), storeID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}
	menu, err := fetchMenu(ctx, firestoreClient, storeID)
	if err != nil {
		log.Printf("failed fetching menu: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "fetch_failed"})
		return
	}
	if menu == nil {
		writeJSON(w, http.StatusOK, menuRecord{StoreID: storeID, Items: []menuItem{}, UpdatedAt: time.Now().UTC()})
		return
	}
	writeJSON(w, http.StatusOK, menu)
}

func handleMenuUpsert(
	ctx context.Context,
	firestoreClient *cloudfirestore.Client,
	cfg *serviceConfig,
	w http.ResponseWriter,
	r *http.Request,
) {
	storeID := chi.URLParam(r, "storeID")
	if storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
		return
	}
	if cfg.RequireAuth && !canAccessStore(r.Context(), storeID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}

	var payload menuRecord
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	normalized := normalizeMenuRecord(&payload)
	if normalized != nil {
		payload = *normalized
	}
	if err := validateMenu(payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	payload.StoreID = storeID
	payload.UpdatedAt = time.Now().UTC()
	if err := upsertMenu(ctx, firestoreClient, payload); err != nil {
		log.Printf("failed to save menu: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "save_failed"})
		return
	}
	invalidateMenuCache(storeID)
	writeJSON(w, http.StatusOK, payload)
}
