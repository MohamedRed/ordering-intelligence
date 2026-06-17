package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func handleGroupOrderCreate(w http.ResponseWriter, r *http.Request, client *cloudfirestore.Client, cfg *serviceConfig) {
	var payload groupOrderCreateRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.TenantID = strings.TrimSpace(payload.TenantID)
	payload.StoreID = strings.TrimSpace(payload.StoreID)
	payload.FulfillmentType = strings.TrimSpace(payload.FulfillmentType)
	payload.DisplayName = strings.TrimSpace(payload.DisplayName)
	payload.ParticipantID = strings.TrimSpace(payload.ParticipantID)
	payload.PaymentMethod = strings.TrimSpace(payload.PaymentMethod)
	payload.CustomerID = strings.TrimSpace(payload.CustomerID)
	if payload.TenantID == "" || payload.StoreID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_store_or_tenant"})
		return
	}
	if !requireGroupOrderStoreAccess(w, r, cfg, payload.StoreID) {
		return
	}
	participantID := participantIDFromContact(payload.Host, payload.ParticipantID)
	if participantID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_participant"})
		return
	}
	name := payload.DisplayName
	if name == "" {
		name = payload.Host.DisplayName
	}
	mode := normalizeGroupPaymentMode(payload.PaymentMode)
	method := normalizeGroupPaymentMethod(payload.PaymentMethod)
	session := groupOrderSession{
		ID:              newGroupOrderID(),
		JoinCode:        "",
		TenantID:        payload.TenantID,
		StoreID:         payload.StoreID,
		CustomerID:      payload.CustomerID,
		FulfillmentType: firstNonEmpty(payload.FulfillmentType, "pickup"),
		Delivery:        payload.Delivery,
		Status:          groupOrderStatusOpen,
		Host:            payload.Host,
		Participants: []groupOrderParticipant{
			{ParticipantID: participantID, Contact: payload.Host, DisplayName: name},
		},
		Items:         []orderItem{},
		PaymentMode:   mode,
		PaymentMethod: method,
		ExpiresAt:     time.Now().UTC().Add(2 * time.Hour),
	}
	session.JoinCode = groupOrderJoinCode(session.ID)
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	if err := createGroupOrderFn(ctx, client, session); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "group_order_create_failed"})
		return
	}
	writeJSON(w, http.StatusOK, groupOrderResponse{GroupOrder: session})
}
