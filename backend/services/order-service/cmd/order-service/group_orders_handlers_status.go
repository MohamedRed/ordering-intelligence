package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

func handleGroupOrderGet(w http.ResponseWriter, r *http.Request, client *cloudfirestore.Client) {
	groupID := strings.TrimSpace(chi.URLParam(r, "groupOrderId"))
	if groupID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	session, err := fetchGroupOrder(ctx, client, groupID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "group_order_not_found"})
		return
	}
	writeJSON(w, http.StatusOK, groupOrderResponse{GroupOrder: session})
}

func handleGroupOrderLock(w http.ResponseWriter, r *http.Request, client *cloudfirestore.Client) {
	groupID := strings.TrimSpace(chi.URLParam(r, "groupOrderId"))
	if groupID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
		return
	}
	var payload groupOrderLockRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	updated, err := updateGroupOrder(ctx, client, groupID, func(current groupOrderSession) (groupOrderSession, error) {
		if current.Status != groupOrderStatusOpen {
			return current, errInvalidGroupStatus
		}
		hostID := participantIDFromContact(current.Host, "")
		current.Pricing = allocateGroupOrderPricing(current.Items, hostID, payload.TaxCents, payload.FeeCents, payload.DiscountCents)
		current.Status = groupOrderStatusLocked
		return current, nil
	})
	if err != nil {
		if errorsIsInvalidStatus(err) {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "group_order_locked"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "group_order_lock_failed"})
		return
	}
	writeJSON(w, http.StatusOK, groupOrderResponse{GroupOrder: updated})
}
