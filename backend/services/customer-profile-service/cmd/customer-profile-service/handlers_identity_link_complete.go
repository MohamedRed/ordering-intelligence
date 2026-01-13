package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

type linkCompleteRequest struct {
	TenantID    string `json:"tenantId,omitempty"`
	Token       string `json:"token"`
	Channel     string `json:"channel"`
	UserID      string `json:"userId"`
	DisplayName string `json:"displayName"`
	Consent     bool   `json:"consent"`
}

func handleLinkComplete(fs *cloudfirestore.Client) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var payload linkCompleteRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_payload"})
			return
		}
		payload.Token = strings.TrimSpace(payload.Token)
		payload.Channel = normalizeChannel(payload.Channel)
		payload.UserID = strings.TrimSpace(payload.UserID)
		payload.DisplayName = strings.TrimSpace(payload.DisplayName)
		if payload.Token == "" || payload.Channel == "" || payload.UserID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing_link_fields"})
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()

		customer, identities, err := processLinkComplete(ctx, fs, payload)
		if err != nil {
			switch {
			case errors.Is(err, errLinkTokenNotFound):
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "link_token_not_found"})
			case errors.Is(err, errLinkTokenExpired):
				writeJSON(w, http.StatusGone, map[string]string{"error": "link_token_expired"})
			case errors.Is(err, errLinkTokenUsed):
				writeJSON(w, http.StatusConflict, map[string]string{"error": "link_token_used"})
			case errors.Is(err, errLinkChannelMismatch):
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "link_token_invalid"})
			case errors.Is(err, errConsentRequired):
				writeJSON(w, http.StatusPreconditionFailed, map[string]string{"error": "consent_required"})
			case errors.Is(err, errCustomerNotFound):
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "customer_not_found"})
			default:
				writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "link_complete_failed"})
			}
			return
		}

		writeJSON(w, http.StatusOK, buildCustomerResponse(customer, identities))
	}
}
