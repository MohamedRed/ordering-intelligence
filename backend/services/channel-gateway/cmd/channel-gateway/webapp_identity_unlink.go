package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

type webAppIdentityUnlinkRequest struct {
	SessionID string `json:"sessionId"`
	Channel   string `json:"channel"`
	UserID    string `json:"userId"`
}

func handleWebAppIdentityUnlink(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	var payload webAppIdentityUnlinkRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.Channel = strings.TrimSpace(payload.Channel)
	payload.UserID = strings.TrimSpace(payload.UserID)
	if payload.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_session"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	session, err := loadSessionWithCustomer(ctx, cfg, firestoreClient, payload.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	channel := payload.Channel
	userID := payload.UserID
	if channel == "" {
		channel = session.Channel
	}
	if userID == "" {
		userID = session.UserID
	}
	if session.CustomerID == "" || channel == "" || userID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_unlink_fields"})
		return
	}

	status, body, err := doCustomerProfileRequest(ctx, cfg.CustomerProfileServiceURL, http.MethodPost, "/v1/customers/unlink", map[string]any{
		"customerId": session.CustomerID,
		"channel":    channel,
		"userId":     userID,
	})
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "customer_profile_unavailable"})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}
