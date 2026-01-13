package main

import (
	"context"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

func handleStoreGroupOrdersList(
	w http.ResponseWriter,
	r *http.Request,
	client *cloudfirestore.Client,
	cfg *serviceConfig,
) {
	storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
	if storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
		return
	}
	if cfg.RequireAuth && !canAccessStore(r.Context(), storeID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}

	statusFilter := strings.TrimSpace(r.URL.Query().Get("status"))
	limit := parseIntDefault(r.URL.Query().Get("limit"), 50)
	if limit > 200 {
		limit = 200
	}
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	orders, err := listGroupOrders(ctx, client, storeID, statusFilter, limit)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "list_failed"})
		return
	}
	writeJSON(w, http.StatusOK, orders)
}

func handleStoreGroupOrderGet(
	w http.ResponseWriter,
	r *http.Request,
	client *cloudfirestore.Client,
	cfg *serviceConfig,
) {
	storeID := strings.TrimSpace(chi.URLParam(r, "storeID"))
	if storeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_id"})
		return
	}
	groupOrderID := strings.TrimSpace(chi.URLParam(r, "groupOrderId"))
	if groupOrderID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
		return
	}
	if cfg.RequireAuth && !canAccessStore(r.Context(), storeID) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	session, err := fetchGroupOrder(ctx, client, groupOrderID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "group_order_not_found"})
		return
	}
	if session.StoreID != storeID {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "group_order_not_found"})
		return
	}
	writeJSON(w, http.StatusOK, groupOrderResponse{GroupOrder: session})
}
