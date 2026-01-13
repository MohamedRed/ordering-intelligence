package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

type webAppIdentityLinkCompleteRequest struct {
	SessionID string `json:"sessionId"`
	Token     string `json:"token"`
	Consent   bool   `json:"consent"`
}

func handleWebAppIdentityLinkComplete(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	var payload webAppIdentityLinkCompleteRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.Token = strings.TrimSpace(payload.Token)
	if payload.SessionID == "" || payload.Token == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_link_fields"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	session, err := loadSessionByID(ctx, firestoreClient, payload.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}

	status, body, err := doCustomerProfileRequest(ctx, cfg.CustomerProfileServiceURL, http.MethodPost, "/v1/customers/link/complete", map[string]any{
		"token":       payload.Token,
		"channel":     session.Channel,
		"userId":      session.UserID,
		"displayName": session.DisplayName,
		"consent":     payload.Consent,
	})
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "customer_profile_unavailable"})
		return
	}
	if status >= 200 && status < 300 {
		var profile customerProfileResponse
		if err := json.Unmarshal(body, &profile); err == nil && profile.CustomerID != "" {
			session.CustomerID = profile.CustomerID
			session.LastSeenAt = time.Now().UTC()
			_ = upsertSession(ctx, firestoreClient, session)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}
