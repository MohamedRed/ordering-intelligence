package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	cloudpubsub "cloud.google.com/go/pubsub"
	"github.com/go-chi/chi/v5"
)

func handleGroupOrderSubmit(w http.ResponseWriter, r *http.Request, client *cloudfirestore.Client, pubsubClient *cloudpubsub.Client, cfg *serviceConfig) {
	groupID := strings.TrimSpace(chi.URLParam(r, "groupOrderId"))
	if groupID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_group_order_id"})
		return
	}
	var payload groupOrderSubmitRequest
	_ = json.NewDecoder(r.Body).Decode(&payload)
	payload.IdempotencyKey = strings.TrimSpace(payload.IdempotencyKey)

	ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
	defer cancel()

	session, err := fetchGroupOrder(ctx, client, groupID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "group_order_not_found"})
		return
	}
	if session.Status == groupOrderStatusSubmitted || session.OrderID != "" {
		writeJSON(w, http.StatusOK, groupOrderResponse{GroupOrder: session})
		return
	}
	if session.Status != groupOrderStatusPaid &&
		session.Status != groupOrderStatusPaymentPending &&
		session.Status != groupOrderStatusLocked {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "group_order_not_ready"})
		return
	}

	if payload.IdempotencyKey == "" {
		payload.IdempotencyKey = "group_order_" + session.ID
	}
	if existing, err := fetchOrderByIdempotencyKey(ctx, client, payload.IdempotencyKey); err == nil && existing != nil {
		session.OrderID = existing.ID
		_, _ = updateGroupOrder(ctx, client, groupID, func(current groupOrderSession) (groupOrderSession, error) {
			current.OrderID = existing.ID
			current.Status = groupOrderStatusSubmitted
			return current, nil
		})
		writeJSON(w, http.StatusOK, groupOrderResponse{GroupOrder: session})
		return
	}

	pricing := groupOrderPricingForSubmit(session)
	order := orderRecordFromGroup(session, pricing, cfg.OrderTTLDays)

	order, err = createOrder(ctx, client, order, payload.IdempotencyKey)
	if err != nil {
		if errors.Is(err, errIdempotencyConflict) {
			if existing, fetchErr := fetchOrderByIdempotencyKey(ctx, client, payload.IdempotencyKey); fetchErr == nil && existing != nil {
				order = *existing
			} else {
				writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_create_failed"})
				return
			}
		} else {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_create_failed"})
			return
		}
	}

	if order.ID == "" {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "order_create_failed"})
		return
	}

	if pubsubClient != nil && cfg.OrdersTopic != "" {
		_ = publishOrderEvent(ctx, pubsubClient, cfg.OrdersTopic, order)
	}

	updated, _ := updateGroupOrder(ctx, client, groupID, func(current groupOrderSession) (groupOrderSession, error) {
		current.Status = groupOrderStatusSubmitted
		current.OrderID = order.ID
		return current, nil
	})
	writeJSON(w, http.StatusOK, groupOrderResponse{GroupOrder: updated})
}
