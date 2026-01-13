package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

type mobileDeviceTokenRequest struct {
	SessionID   string `json:"sessionId"`
	DeviceToken string `json:"deviceToken"`
	Platform    string `json:"platform"`
	DeviceID    string `json:"deviceId"`
	Locale      string `json:"locale"`
}

func handleMobileDeviceTokenRegister(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	var payload mobileDeviceTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.DeviceToken = strings.TrimSpace(payload.DeviceToken)
	payload.Platform = strings.TrimSpace(payload.Platform)
	payload.DeviceID = strings.TrimSpace(payload.DeviceID)

	if payload.SessionID == "" || payload.DeviceToken == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_fields"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()

	session, err := loadSessionWithCustomer(ctx, cfg, firestoreClient, payload.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	customerID := strings.TrimSpace(session.CustomerID)
	if customerID == "" {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "customer_not_resolved"})
		return
	}

	platform := payload.Platform
	if platform == "" {
		platform = strings.TrimSpace(session.ClientPlatform)
	}
	if platform == "" {
		platform = "mobile"
	}

	payloadMap := map[string]any{
		"token":      payload.DeviceToken,
		"userId":     customerID,
		"customerId": customerID,
		"tenantId":   strings.TrimSpace(session.TenantID),
		"storeId":    strings.TrimSpace(session.StoreID),
		"platform":   platform,
		"deviceId":   payload.DeviceID,
		"source":     "consumer_mobile",
		"updatedAt":  time.Now().UTC(),
	}
	_, err = firestoreClient.Collection("deviceTokens").Doc(payload.DeviceToken).Set(ctx, payloadMap, cloudfirestore.MergeAll)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "device_token_write_failed"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
