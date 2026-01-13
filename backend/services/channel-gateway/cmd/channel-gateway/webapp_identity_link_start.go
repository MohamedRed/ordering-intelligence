package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

type webAppIdentityLinkStartRequest struct {
	SessionID     string `json:"sessionId"`
	TargetChannel string `json:"targetChannel"`
	Consent       bool   `json:"consent"`
}

func handleWebAppIdentityLinkStart(
	w http.ResponseWriter,
	r *http.Request,
	cfg *serviceConfig,
	firestoreClient *cloudfirestore.Client,
) {
	var payload webAppIdentityLinkStartRequest
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
		return
	}
	payload.SessionID = strings.TrimSpace(payload.SessionID)
	payload.TargetChannel = strings.TrimSpace(payload.TargetChannel)
	if payload.SessionID == "" || payload.TargetChannel == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_link_fields"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	session, err := loadSessionWithCustomer(ctx, cfg, firestoreClient, payload.SessionID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "session_not_found"})
		return
	}
	if session.CustomerID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_customer"})
		return
	}

	status, body, err := doCustomerProfileRequest(ctx, cfg.CustomerProfileServiceURL, http.MethodPost, "/v1/customers/link/start", map[string]any{
		"customerId":    session.CustomerID,
		"targetChannel": payload.TargetChannel,
		"consent":       payload.Consent,
	})
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "customer_profile_unavailable"})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}
