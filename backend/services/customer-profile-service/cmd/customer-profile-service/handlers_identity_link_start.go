package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

type linkStartRequest struct {
	TenantID      string `json:"tenantId,omitempty"`
	CustomerID    string `json:"customerId"`
	TargetChannel string `json:"targetChannel"`
	Consent       bool   `json:"consent"`
}

type linkStartResponse struct {
	Token         string    `json:"token"`
	ExpiresAt     time.Time `json:"expiresAt"`
	TargetChannel string    `json:"targetChannel"`
	CustomerID    string    `json:"customerId"`
}

func handleLinkStart(fs *cloudfirestore.Client) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var payload linkStartRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		payload.CustomerID = strings.TrimSpace(payload.CustomerID)
		payload.TargetChannel = normalizeChannel(payload.TargetChannel)
		if payload.CustomerID == "" || payload.TargetChannel == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_link_fields"})
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancel()
		customer, err := resolveActiveCustomer(ctx, fs, payload.CustomerID)
		if err != nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "customer_not_found"})
			return
		}
		if _, err := ensureCustomerConsent(ctx, fs, customer, payload.Consent); err != nil {
			if err == errConsentRequired {
				writeJSON(w, http.StatusPreconditionFailed, map[string]string{"error": "consent_required"})
				return
			}
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "consent_update_failed"})
			return
		}

		record, err := createLinkToken(ctx, fs, customer.CustomerID, payload.TargetChannel, 15*time.Minute)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "link_token_failed"})
			return
		}
		writeJSON(w, http.StatusOK, linkStartResponse{
			Token:         record.Token,
			ExpiresAt:     record.ExpiresAt,
			TargetChannel: record.TargetChannel,
			CustomerID:    customer.CustomerID,
		})
	}
}
